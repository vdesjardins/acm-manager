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
	"strings"
	"time"

	certificatev1alpha1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
	certificateclient "vdesjardins/acm-manager/pkg/client/versioned"

	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	networkingv1ac "k8s.io/client-go/applyconfigurations/networking/v1"
	"k8s.io/client-go/kubernetes"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

const (
	IngressClassValue        = "alb"
	IngressSchemeKey         = "alb.ingress.kubernetes.io/scheme"
	IngressSchemeValue       = "internet-facing"
	IngressCertificateArnKey = "alb.ingress.kubernetes.io/certificate-arn"

	ACMManagerCreateCertificateKey = "acm-manager.io/enable"
)

var IngressAutoDetect = true

// IngressReconciler reconciles a Ingress object
type IngressReconciler struct {
	client.Client
	clientset  *kubernetes.Clientset
	certClient certificateclient.Interface
	Scheme     *runtime.Scheme
}

//+kubebuilder:rbac:groups=networking.k8s.io,resources=ingresses,verbs=get;list;watch;update;patch

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.10.0/pkg/reconcile
func (r *IngressReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := log.FromContext(ctx)

	ingress := &networkingv1.Ingress{}
	if err := r.Get(ctx, req.NamespacedName, ingress); err != nil {
		log.Error(err, "unable to fetch ingress")
		// we'll ignore not-found errors, since they can't be fixed by an immediate
		// requeue (we'll need to wait for a new notification), and we can get them
		// on deleted requests.
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	// if deleting do not sync
	if !ingress.DeletionTimestamp.IsZero() {
		log.Info("ingress marked for deletion. skipping certificate generation")
		return ctrl.Result{}, nil
	}

	// check for annotation that enable/disable auto cert creation
	if !isIngressShouldCreateCert(ingress) {
		log.Info("ingress does not meet annotattion criteria. skipping certificate generation")
		return ctrl.Result{}, nil
	}

	cert := &certificatev1alpha1.Certificate{}
	newCert := false
	if err := r.Get(ctx, req.NamespacedName, cert); err != nil {
		if apierrors.IsNotFound(err) {
			newCert = true
			cert.Name = req.Name
			cert.Namespace = req.Namespace
		} else {
			log.Error(err, "error loading certificate for ingress")
			return ctrl.Result{}, err
		}
	} else {
		if len(cert.GetOwnerReferences()) == 0 ||
			cert.GetOwnerReferences()[0].Kind != "Ingress" ||
			cert.GetOwnerReferences()[0].Name != req.Name {
			return ctrl.Result{}, nil
		}
	}

	hostMap := map[string]bool{}
	for _, t := range ingress.Spec.TLS {
		if t.SecretName != "" {
			continue
		}
		for _, h := range t.Hosts {
			hostMap[h] = true
		}
	}
	hosts := make([]string, 0, len(hostMap))
	for k := range hostMap {
		hosts = append(hosts, k)
	}

	if len(hosts) == 0 {
		log.Info("no host declared in ingress's resource. skipping certificate generation")
		return ctrl.Result{}, nil
	}

	cert.Spec.CommonName = hosts[0]
	cert.Spec.SubjectAlternativeNames = hosts
	ctrl.SetControllerReference(metav1.Object(ingress), cert, r.Scheme)

	if newCert {
		if err := r.Create(ctx, cert); err != nil {
			log.Error(err, "unable to create certificate for ingress")
			return ctrl.Result{}, err
		}
	} else {
		if err := updateStatus(ctx, r.certClient, cert); err != nil {
			log.Error(err, "unable to update certificate for ingress")
			return ctrl.Result{}, err
		}
	}

	// update ingress with certificate ARN if available. if not requeue
	if cert.Status.CertificateArn == "" || cert.Status.Status != certificatev1alpha1.CertificateStatusIssued {
		return ctrl.Result{
			RequeueAfter: time.Second * 10,
		}, nil
	}
	if ingress.GetAnnotations()[IngressCertificateArnKey] != cert.Status.CertificateArn {
		ingac := networkingv1ac.Ingress(ingress.GetName(), ingress.GetNamespace()).
			WithAnnotations(map[string]string{IngressCertificateArnKey: cert.Status.CertificateArn})

		_, err := r.clientset.NetworkingV1().Ingresses(ingress.Namespace).
			Apply(ctx, ingac, metav1.ApplyOptions{FieldManager: ACMManagerFieldManager, Force: true})
		if err != nil {
			log.Error(err, "unable to update ingress with certificate arn")
			return ctrl.Result{}, err
		}
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *IngressReconciler) SetupWithManager(mgr ctrl.Manager) error {
	log := log.FromContext(context.TODO())

	var err error
	r.certClient, err = certificateclient.NewForConfig(mgr.GetConfig())
	if err != nil {
		log.Error(err, "unable to initialize certificate client")
		return err
	}
	r.clientset, err = kubernetes.NewForConfig(mgr.GetConfig())
	if err != nil {
		log.Error(err, "unable to initialize kubernetes client")
		return err
	}

	return ctrl.NewControllerManagedBy(mgr).
		For(&networkingv1.Ingress{}).
		Owns(&certificatev1alpha1.Certificate{}).
		Complete(r)
}

func isIngressShouldCreateCert(ingress *networkingv1.Ingress) bool {
	enabled := strings.ToLower(ingress.GetAnnotations()[ACMManagerCreateCertificateKey])
	if enabled == "true" || enabled == "yes" {
		return true
	}
	if enabled == "false" || enabled == "no" {
		return false
	}

	if IngressAutoDetect && ingress.Spec.IngressClassName != nil && *ingress.Spec.IngressClassName == IngressClassValue &&
		ingress.GetAnnotations()[IngressSchemeKey] == IngressSchemeValue {
		return true
	}

	return false
}
