/*
Copyright 2021 The acm-manager Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controllers

import (
	"context"
	"errors"
	"fmt"
	"time"
	"vdesjardins/acm-manager/pkg/controllers/external_api_clients"

	certac "vdesjardins/acm-manager/pkg/client/applyconfiguration/acmmanager/v1alpha1"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/acm"
	acmtypes "github.com/aws/aws-sdk-go-v2/service/acm/types"
	"github.com/aws/smithy-go"
	multierror "github.com/hashicorp/go-multierror"
	core "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"
	dnsendpoint "sigs.k8s.io/external-dns/apis/v1alpha1"
	endpoint "sigs.k8s.io/external-dns/endpoint"

	certificatev1alpha1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
	certificateclient "vdesjardins/acm-manager/pkg/client/versioned"
)

var (
	ACMManagerOwnerName           = "acm-manager"
	ACMManagerFieldManager        = "acm-manager"
	ACMCertificateCleanupInterval = 6 * time.Hour
)

const (
	TagCertificateOwner     = "acm-manager/owner"
	TagCertificateNamespace = "acm-manager/certificate-namespace"
	TagCertificateName      = "acm-manager/certificate-name"
)

const (
	CertificateEventSuccessfulSync = "SuccessfulSync"
	CertificateEventRequestError   = "RequestError"
	CertificateEventCompareError   = "CompareError"
	CertificateEventUpdateError    = "UpdateError"
	CertificateEventCleanupError   = "CleanupError"
	CertificateEventCleanupSuccess = "SuccessfulCleanup"
)

// CertificateReconciler reconciles a Certificate object
type CertificateReconciler struct {
	client.Client
	certClient certificateclient.Interface
	Scheme     *runtime.Scheme
	svc        external_api_clients.AcmAWSAPI
	recorder   record.EventRecorder
}

//+kubebuilder:rbac:groups=acm-manager.io,resources=certificates,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=acm-manager.io,resources=certificates/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=acm-manager.io,resources=certificates/finalizers,verbs=update
//+kubebuilder:rbac:groups=externaldns.k8s.io,resources=dnsendpoints,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups="",resources=events,verbs=create;patch

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.10.0/pkg/reconcile
func (r *CertificateReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := log.FromContext(ctx)

	certificate := &certificatev1alpha1.Certificate{}
	if err := r.Get(ctx, req.NamespacedName, certificate); err != nil {
		log.Error(err, "unable to fetch Certificate")
		// we'll ignore not-found errors, since they can't be fixed by an immediate
		// requeue (we'll need to wait for a new notification), and we can get them
		// on deleted requests.
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	// name of our custom finalizer
	finalizerName := "certificate.acm-manager.io/finalizer"

	// examine DeletionTimestamp to determine if object is under deletion
	if certificate.DeletionTimestamp.IsZero() {
		// The object is not being deleted, so if it does not have our finalizer,
		// then lets add the finalizer and update the object. This is equivalent
		// registering our finalizer.
		if !containsString(certificate.GetFinalizers(), finalizerName) {
			controllerutil.AddFinalizer(certificate, finalizerName)
			if err := r.Update(ctx, certificate); err != nil {
				return ctrl.Result{}, err
			}
		}
	} else {
		// The object is being deleted
		if containsString(certificate.GetFinalizers(), finalizerName) {
			// our finalizer is present, so lets handle any external dependency
			if err := r.deleteACMCertificate(ctx, certificate); err != nil {
				// if fail to delete the external dependency here, return with error
				// so that it can be retried
				return ctrl.Result{}, err
			}

			// remove our finalizer from the list and update it.
			controllerutil.RemoveFinalizer(certificate, finalizerName)
			if err := r.Update(ctx, certificate); err != nil {
				return ctrl.Result{}, err
			}
		}

		// Stop reconciliation as the item is being deleted
		return ctrl.Result{}, nil
	}

	// create cert request if does not exist
	certificateCreated := false
	if certificate.Status.CertificateArn == "" {
		if err := r.requestACMCertificate(ctx, certificate); err != nil {
			log.Error(err, "unable to request certificate")
			r.recorder.Event(certificate, core.EventTypeWarning, CertificateEventRequestError, err.Error())
			certificate.Status.Status = certificatev1alpha1.CertificateStatusError
			if err := r.updateWithStatus(ctx, certificate); err != nil {
				log.Error(err, "unable to update status")
			}
			return ctrl.Result{}, err
		}
		certificateCreated = true
	} else {
		// if exists need to check if it has changed
		equals, err := r.compareACMCertificate(ctx, certificate)
		if err != nil {
			log.Error(err, "unable to update ACM certificate")
			r.recorder.Event(certificate, core.EventTypeWarning, CertificateEventCompareError, err.Error())
			return ctrl.Result{}, err
		}
		if !equals {
			// create a new cert request
			// first, clear status
			if err := r.requestACMCertificate(ctx, certificate); err != nil {
				log.Error(err, "unable to request certificate")
				r.recorder.Event(certificate, core.EventTypeWarning, CertificateEventRequestError, err.Error())
				certificate.Status.Status = certificatev1alpha1.CertificateStatusError
				if err := r.updateWithStatus(ctx, certificate); err != nil {
					log.Error(err, "unable to update status")
				}
				return ctrl.Result{}, err
			}
			// clear status
			certificate.Status.ResourceRecords = []certificatev1alpha1.ResourceRecord{}
			certificateCreated = true
		}
	}

	// save status state
	if err := r.updateWithStatus(ctx, certificate); err != nil {
		log.Error(err, "unable to update certificate resource status")
		r.recorder.Event(certificate, core.EventTypeWarning, CertificateEventUpdateError, err.Error())
		if certificateCreated {
			r.deleteACMCertificate(ctx, certificate)
		}
		return ctrl.Result{}, err
	}

	// update certificate information from ACM if available
	requeue, err := r.updateCertificateInfo(ctx, certificate)
	if err != nil {
		log.Error(err, "unable to update certificate info")
		r.recorder.Event(certificate, core.EventTypeWarning, CertificateEventUpdateError, err.Error())
		if certificateCreated {
			r.deleteACMCertificate(ctx, certificate)
		}
		return ctrl.Result{}, err
	}

	// save status state
	if err := r.updateWithStatus(ctx, certificate); err != nil {
		log.Error(err, "unable to update certificate resource status")
		r.recorder.Event(certificate, core.EventTypeWarning, CertificateEventUpdateError, err.Error())
		if certificateCreated {
			r.deleteACMCertificate(ctx, certificate)
		}
		return ctrl.Result{}, err
	}

	// requeue if information not yet available from ACM
	if requeue {
		return ctrl.Result{
			Requeue:      true,
			RequeueAfter: time.Second * 5,
		}, nil
	}

	// sync DNS endpoints for certificate validation
	if err := r.syncDNSEndpoints(ctx, certificate); err != nil {
		log.Error(err, "error synching DNS endpoints")
		r.recorder.Event(certificate, core.EventTypeWarning, CertificateEventUpdateError, err.Error())
		return ctrl.Result{}, err
	}

	// requeue if certificate not yet issued
	if certificate.Status.Status != certificatev1alpha1.CertificateStatusIssued {
		return ctrl.Result{
			Requeue:      true,
			RequeueAfter: time.Second * 15,
		}, nil
	} else {
		r.recorder.Event(certificate, core.EventTypeNormal, CertificateEventSuccessfulSync, "Certificate sync succeeeded")
	}

	// cleanup old ACM certificates
	nbCleanedUp, err := r.cleanupACMCertificates(ctx, certificate)
	if err != nil {
		log.Error(err, "error cleaning up old certificate")
		var ae smithy.APIError
		if errors.As(err, &ae) {
			r.recorder.Event(certificate, core.EventTypeWarning, CertificateEventCleanupError, ae.ErrorCode())
		}
		return ctrl.Result{
			Requeue:      true,
			RequeueAfter: time.Second * 5,
		}, nil
	}
	if nbCleanedUp > 0 {
		r.recorder.Event(certificate, core.EventTypeNormal, CertificateEventCleanupSuccess, fmt.Sprintf("%d certificate(s) cleaned up in ACM", nbCleanedUp))
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *CertificateReconciler) SetupWithManager(mgr ctrl.Manager) error {
	log := log.FromContext(context.TODO())

	r.recorder = mgr.GetEventRecorderFor("Certificate")

	var err error
	r.certClient, err = certificateclient.NewForConfig(mgr.GetConfig())
	if err != nil {
		log.Error(err, "unable to initialize certificate client")
		return err
	}

	cfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		return err
	}
	r.svc = external_api_clients.NewAcmClient(acm.NewFromConfig(cfg))

	return ctrl.NewControllerManagedBy(mgr).
		For(&certificatev1alpha1.Certificate{}).
		Owns(&dnsendpoint.DNSEndpoint{}).
		Complete(r)
}

func (r *CertificateReconciler) compareACMCertificate(ctx context.Context, cert *certificatev1alpha1.Certificate) (bool, error) {
	detail, err := r.getACMCertificateDetail(ctx, cert)
	if err != nil {
		var apiErr smithy.APIError
		if !errors.As(err, &apiErr) || apiErr.ErrorCode() != "ResourceNotFoundException" {
			return false, fmt.Errorf("unable to retreive certificate detail to perform comparision: %w", err)
		}
	}

	if *detail.DomainName != cert.Spec.CommonName {
		return false, nil
	}
	if len(detail.SubjectAlternativeNames) != len(cert.Spec.SubjectAlternativeNames) {
		return false, nil
	}

	dnsNames := map[string]bool{}
	for _, domain := range detail.SubjectAlternativeNames {
		dnsNames[domain] = true
	}

	for _, dnsName := range cert.Spec.SubjectAlternativeNames {
		if _, ok := dnsNames[dnsName]; !ok {
			return false, nil
		}
	}

	return true, nil
}

func (r *CertificateReconciler) requestACMCertificate(ctx context.Context, cert *certificatev1alpha1.Certificate) error {
	acmReq := newRequestCertificateInput(cert)
	resp, err := r.svc.RequestCertificate(ctx, acmReq)
	if err != nil {
		return fmt.Errorf("unable to request certificate: %w", err)
	}

	cert.Status.CertificateArn = *resp.CertificateArn
	cert.Status.Status = certificatev1alpha1.CertificateStatusRequested

	return nil
}

func (r *CertificateReconciler) updateCertificateInfo(ctx context.Context, cert *certificatev1alpha1.Certificate) (bool, error) {
	detail, err := r.getACMCertificateDetail(ctx, cert)
	if err != nil {
		return true, fmt.Errorf("unable to retreive certificate detail for update: %w", err)
	}

	records := []certificatev1alpha1.ResourceRecord{}
	for _, d := range detail.DomainValidationOptions {
		if d.ResourceRecord == nil {
			return true, nil
		}
		records = append(records, certificatev1alpha1.ResourceRecord{
			Name:  *d.ResourceRecord.Name,
			Type:  string(d.ResourceRecord.Type),
			Value: *d.ResourceRecord.Value,
		})
	}
	cert.Status.ResourceRecords = records

	if detail.NotBefore != nil {
		t := metav1.NewTime(*detail.NotBefore)
		cert.Status.NotBefore = &t
	}
	if detail.NotAfter != nil {
		t := metav1.NewTime(*detail.NotAfter)
		cert.Status.NotAfter = &t
	}

	cert.Status.Status = convertFrom(detail.Status)

	return false, nil
}

func (r *CertificateReconciler) getACMCertificateDetail(ctx context.Context, cert *certificatev1alpha1.Certificate) (*acmtypes.CertificateDetail, error) {
	input := &acm.DescribeCertificateInput{CertificateArn: aws.String(cert.Status.CertificateArn)}
	resp, err := r.svc.DescribeCertificate(ctx, input)
	if err != nil {
		return nil, fmt.Errorf("unable to retreive certificate with ARN %s: %w", cert.Status.CertificateArn, err)
	}

	return resp.Certificate, nil
}

func newRequestCertificateInput(cert *certificatev1alpha1.Certificate) *acm.RequestCertificateInput {
	req := &acm.RequestCertificateInput{
		DomainName:              aws.String(cert.Spec.CommonName),
		SubjectAlternativeNames: cert.Spec.SubjectAlternativeNames,
		ValidationMethod:        acmtypes.ValidationMethodDns,
		Tags: []acmtypes.Tag{
			{
				Key:   aws.String(TagCertificateOwner),
				Value: aws.String(ACMManagerOwnerName),
			}, {
				Key:   aws.String(TagCertificateNamespace),
				Value: aws.String(cert.Namespace),
			}, {
				Key:   aws.String(TagCertificateName),
				Value: aws.String(cert.Name),
			},
		},
	}

	return req
}

func (r *CertificateReconciler) deleteACMCertificate(ctx context.Context, cert *certificatev1alpha1.Certificate) error {
	if cert.Status.CertificateArn == "" {
		return nil
	}

	input := &acm.DeleteCertificateInput{
		CertificateArn: aws.String(cert.Status.CertificateArn),
	}

	_, err := r.svc.DeleteCertificate(ctx, input)
	if err != nil {
		var apiErr smithy.APIError
		if !errors.As(err, &apiErr) || apiErr.ErrorCode() != "ResourceNotFoundException" {
			return fmt.Errorf("unable to delete certificate with ARN: %s: %w", cert.Status.CertificateArn, err)
		}
	}

	return nil
}

func (r *CertificateReconciler) cleanupACMCertificates(ctx context.Context, cert *certificatev1alpha1.Certificate) (int, error) {
	var result error

	nbCleanedUp := 0

	input := &acm.ListCertificatesInput{
		// MaxItems:            new(int32),
		// NextToken:           new(string),
	}
	output, err := r.svc.ListCertificates(ctx, input)
	if err != nil {
		return nbCleanedUp, fmt.Errorf("unable to list certificates: %w", err)
	}

	for _, summary := range output.CertificateSummaryList {
		log := log.FromContext(ctx).WithValues("ARN", *summary.CertificateArn)
		if *summary.CertificateArn == cert.Status.CertificateArn {
			continue
		}
		input := &acm.ListTagsForCertificateInput{
			CertificateArn: summary.CertificateArn,
		}
		output, err := r.svc.ListTagsForCertificate(ctx, input)
		if err != nil {
			return nbCleanedUp, fmt.Errorf("unable to retrieve list of tags for certificate %s/%s: %w", cert.Namespace, cert.Name, err)
		}

		tags := make(map[string]string, len(output.Tags))
		for _, t := range output.Tags {
			tags[*t.Key] = *t.Value
		}

		if tags[TagCertificateOwner] == ACMManagerOwnerName && tags[TagCertificateNamespace] == cert.Namespace && tags[TagCertificateName] == cert.Name {
			if err := r.deleteACMCertificate(ctx, &certificatev1alpha1.Certificate{
				Status: certificatev1alpha1.CertificateStatus{
					CertificateArn: *summary.CertificateArn,
				},
			}); err != nil {
				result = multierror.Append(result, err)
			} else {
				log.Info("certificate deleted in ACM")
				nbCleanedUp += 1
			}
		}
	}

	return nbCleanedUp, result
}

func (r *CertificateReconciler) syncDNSEndpoints(ctx context.Context, cert *certificatev1alpha1.Certificate) error {
	dnsEndpoint := &dnsendpoint.DNSEndpoint{}
	nsName := types.NamespacedName{Name: cert.Name, Namespace: cert.Namespace}
	newEndpoint := false
	if err := r.Get(ctx, nsName, dnsEndpoint); err != nil {
		if client.IgnoreNotFound(err) != nil {
			return fmt.Errorf("unable to list DNSEndpoints: %w", err)
		}

		newEndpoint = true
		dnsEndpoint.Name = cert.Name
		dnsEndpoint.Namespace = cert.Namespace
		ctrl.SetControllerReference(metav1.Object(cert), dnsEndpoint, r.Scheme)
	}

	endpoints := []*endpoint.Endpoint{}

	for _, rr := range cert.Status.ResourceRecords {
		endpoints = append(endpoints, endpoint.NewEndpoint(rr.Name, rr.Type, rr.Value))
	}
	dnsEndpoint.Spec.Endpoints = endpoints

	var err error
	if newEndpoint {
		err = r.Create(ctx, dnsEndpoint)
	} else {
		err = r.Update(ctx, dnsEndpoint)
	}
	if err != nil {
		return fmt.Errorf("unable to save DNSEndpoint in kubernetes: %w", err)
	}

	return nil
}

func (r *CertificateReconciler) updateWithStatus(ctx context.Context, cert *certificatev1alpha1.Certificate) error {
	return updateCertificateWithStatus(ctx, r.certClient, cert)
}

// Helper functions to check and remove string from a slice of strings.
func containsString(slice []string, s string) bool {
	for _, item := range slice {
		if item == s {
			return true
		}
	}
	return false
}

func removeString(slice []string, s string) (result []string) {
	for _, item := range slice {
		if item == s {
			continue
		}
		result = append(result, item)
	}
	return
}

func convertFrom(status acmtypes.CertificateStatus) certificatev1alpha1.CertificateStatusType {
	switch status {
	case acmtypes.CertificateStatusPendingValidation:
		return certificatev1alpha1.CertificateStatusPendingValidation
	case acmtypes.CertificateStatusIssued:
		return certificatev1alpha1.CertificateStatusIssued
	case acmtypes.CertificateStatusInactive:
		return certificatev1alpha1.CertificateStatusInactive
	case acmtypes.CertificateStatusExpired:
		return certificatev1alpha1.CertificateStatusExpired
	case acmtypes.CertificateStatusValidationTimedOut:
		return certificatev1alpha1.CertificateStatusValidationTimedOut
	case acmtypes.CertificateStatusRevoked:
		return certificatev1alpha1.CertificateStatusRevoked
	case acmtypes.CertificateStatusFailed:
		return certificatev1alpha1.CertificateStatusFailed
	default:
		return certificatev1alpha1.CertificateStatusUnknown
	}
}

func StartACMCertificateCleanupJob() {
	ticker := time.NewTicker(ACMCertificateCleanupInterval)
	go func() {
		for range ticker.C {
			cleanupOrphanACMCertificates()
		}
	}()
}

func cleanupOrphanACMCertificates() {
	ctx := context.Background()
	log := log.FromContext(ctx).WithName("background cleanup")

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Error(err, "unable to load config")
		return
	}
	acmClient := external_api_clients.NewAcmClient(acm.NewFromConfig(cfg))

	certClient, err := external_api_clients.NewCertificateRestClient(ctx)

	input := &acm.ListCertificatesInput{
		// MaxItems:            new(int32),
		// NextToken:           new(string),
	}
	output, err := acmClient.ListCertificates(ctx, input)
	if err != nil {
		log.Error(err, "unable to list certificates")
		return
	}
	for _, summary := range output.CertificateSummaryList {
		log := log.WithValues("ARN", *summary.CertificateArn)

		input := &acm.ListTagsForCertificateInput{
			CertificateArn: summary.CertificateArn,
		}
		output, err := acmClient.ListTagsForCertificate(ctx, input)
		if err != nil {
			log.Error(err, "unable to list certificate tags")
			continue
		}

		tags := make(map[string]string, len(output.Tags))
		for _, t := range output.Tags {
			tags[*t.Key] = *t.Value
		}

		if tags[TagCertificateOwner] != ACMManagerOwnerName {
			continue
		}

		_, err = certClient.GetCertificateForNamespace(ctx, tags[TagCertificateNamespace], tags[TagCertificateName], metav1.GetOptions{})
		if err != nil {
			if apierrors.IsNotFound(err) {
				if _, err := acmClient.DeleteCertificate(ctx, &acm.DeleteCertificateInput{
					CertificateArn: summary.CertificateArn,
				}); err != nil {
					log.Error(err, "unable to delete unused owned certificate")
					continue
				}
				log.Info("certificate deleted in ACM")
			}
		}
	}
}

func updateCertificate(ctx context.Context, certClient certificateclient.Interface, cert *certificatev1alpha1.Certificate) error {
	if _, err := certClient.AcmmanagerV1alpha1().Certificates(cert.Namespace).
		Apply(ctx,
			ApplyConfigurationFromCertificate(cert),
			metav1.ApplyOptions{FieldManager: ACMManagerFieldManager, Force: true}); err != nil {
		return fmt.Errorf("failed to apply certificate resource: %w", err)
	}
	return nil
}

func updateCertificateWithStatus(ctx context.Context, certClient certificateclient.Interface, cert *certificatev1alpha1.Certificate) error {
	if _, err := certClient.AcmmanagerV1alpha1().Certificates(cert.Namespace).
		ApplyStatus(ctx,
			ApplyConfigurationFromCertificate(cert),
			metav1.ApplyOptions{FieldManager: ACMManagerFieldManager, Force: true}); err != nil {
		return fmt.Errorf("failed to apply certificate status subresource: %w", err)
	}
	return nil
}

func ApplyConfigurationFromCertificate(c *certificatev1alpha1.Certificate) *certac.CertificateApplyConfiguration {
	rr := []*certac.ResourceRecordApplyConfiguration{}
	for _, d := range c.Status.ResourceRecords {
		rr = append(rr, certac.ResourceRecord().
			WithName(d.Name).
			WithType(d.Type).
			WithValue(d.Value))
	}

	status := certac.CertificateStatus().
		WithCertificateArn(c.Status.CertificateArn).
		WithStatus(c.Status.Status).
		WithResourceRecords(rr...)

	if c.Status.NotAfter != nil {
		status.WithNotAfter(*c.Status.NotAfter)
	}
	if c.Status.NotBefore != nil {
		status.WithNotBefore(*c.Status.NotBefore)
	}

	spec := certac.CertificateSpec().
		WithCommonName(c.Spec.CommonName).
		WithSubjectAlternativeNames(c.Spec.SubjectAlternativeNames...)

	return certac.Certificate(c.Name, c.Namespace).
		WithSpec(spec).
		WithStatus(status)
}
