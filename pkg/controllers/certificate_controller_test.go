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
	"time"

	certificatev1alpha1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/acm"
	acmtypes "github.com/aws/aws-sdk-go-v2/service/acm/types"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	dnsendpoint "sigs.k8s.io/external-dns/endpoint"
)

type acmClientMock struct{}

func init() {
	newAcmClient = func(service *acm.Client) acmAPI {
		return &acmClientMock{}
	}
}

func (a *acmClientMock) DescribeCertificate(ctx context.Context, params *acm.DescribeCertificateInput, optFns ...func(*acm.Options)) (*acm.DescribeCertificateOutput, error) {
	return &acm.DescribeCertificateOutput{
		Certificate: &acmtypes.CertificateDetail{
			CertificateArn: aws.String("test-arn"),
			DomainName:     aws.String("test.local"),
			DomainValidationOptions: []acmtypes.DomainValidation{
				{
					ResourceRecord: &acmtypes.ResourceRecord{
						Name:  aws.String("dns.validation.key"),
						Value: aws.String("dns.validation.value"),
						Type:  acmtypes.RecordTypeCname,
					},
				},
			},
			SubjectAlternativeNames: []string{"test.local"},
			Status:                  acmtypes.CertificateStatusIssued,
		},
	}, nil
}

func (a *acmClientMock) RequestCertificate(ctx context.Context, params *acm.RequestCertificateInput, optFns ...func(*acm.Options)) (*acm.RequestCertificateOutput, error) {
	return &acm.RequestCertificateOutput{
		CertificateArn: aws.String("test-arn"),
	}, nil
}

func (a *acmClientMock) DeleteCertificate(ctx context.Context, params *acm.DeleteCertificateInput, optFns ...func(*acm.Options)) (*acm.DeleteCertificateOutput, error) {
	return nil, nil
}

func (a *acmClientMock) ListCertificates(ctx context.Context, params *acm.ListCertificatesInput, optFns ...func(*acm.Options)) (*acm.ListCertificatesOutput, error) {
	return &acm.ListCertificatesOutput{}, nil
}

func (a *acmClientMock) ListTagsForCertificate(ctx context.Context, params *acm.ListTagsForCertificateInput, optFns ...func(*acm.Options)) (*acm.ListTagsForCertificateOutput, error) {
	return &acm.ListTagsForCertificateOutput{}, nil
}

var _ = Describe("Certificate controller", func() {
	const (
		timeout  = time.Second * 10
		duration = time.Second * 10
		interval = time.Millisecond * 250
	)

	Context("When creating Certificate", func() {
		It("Should update certificate arn in status", func() {
			By("By creating a new Certificate")
			certName := "test-cert"
			certNamespace := "default"

			ctx := context.Background()
			cert := newCert(certName, certNamespace)
			Expect(k8sClient.Create(ctx, cert)).Should(Succeed())

			certLookupKey := types.NamespacedName{Name: certName, Namespace: certNamespace}
			createdCert := &certificatev1alpha1.Certificate{}

			By("By checking that certificate arn is set")
			Eventually(func() bool {
				err := k8sClient.Get(ctx, certLookupKey, createdCert)
				if err != nil {
					return false
				}
				return createdCert.Status.CertificateArn != ""
			}, timeout, interval).Should(BeTrue())

			By("Deleting the certificate")
			Expect(k8sClient.Delete(ctx, createdCert)).Should(Succeed())
		})

		It("Should update dns records in status", func() {
			By("By creating a new Certificate")
			certName := "test-cert-dns"
			certNamespace := "default"

			ctx := context.Background()
			cert := newCert(certName, certNamespace)
			Expect(k8sClient.Create(ctx, cert)).Should(Succeed())

			certLookupKey := types.NamespacedName{Name: certName, Namespace: certNamespace}
			createdCert := &certificatev1alpha1.Certificate{}

			By("By checking that resource records are set")
			Eventually(func() bool {
				err := k8sClient.Get(ctx, certLookupKey, createdCert)
				if err != nil {
					return false
				}
				return len(createdCert.Status.ResourceRecords) > 0
			}, timeout, interval).Should(BeTrue())

			Expect(createdCert.Status.ResourceRecords[0].Name).Should(Equal("dns.validation.key"))
			Expect(createdCert.Status.ResourceRecords[0].Value).Should(Equal("dns.validation.value"))
			Expect(createdCert.Status.ResourceRecords[0].Type).Should(Equal("CNAME"))

			By("Deleting the certificate")
			Expect(k8sClient.Delete(ctx, createdCert)).Should(Succeed())
		})

		It("Should create dns endpoint", func() {
			By("By creating a new Certificate")
			certName := "test-cert-endpoint"
			certNamespace := "default"

			ctx := context.Background()
			cert := newCert(certName, certNamespace)
			Expect(k8sClient.Create(ctx, cert)).Should(Succeed())

			endpointLookupKey := types.NamespacedName{Name: certName, Namespace: certNamespace}
			createdEndpoint := &dnsendpoint.DNSEndpoint{}

			By("By checking that resource records are set")
			Eventually(func() bool {
				err := k8sClient.Get(ctx, endpointLookupKey, createdEndpoint)
				return err == nil
			}, timeout, interval).Should(BeTrue())

			Expect(createdEndpoint.Spec.Endpoints[0].DNSName).Should(Equal("dns.validation.key"))
			Expect(createdEndpoint.Spec.Endpoints[0].Targets[0]).Should(Equal("dns.validation.value"))
			Expect(createdEndpoint.Spec.Endpoints[0].RecordType).Should(Equal("CNAME"))

			By("Deleting the certificate")
			Expect(k8sClient.Delete(ctx, cert)).Should(Succeed())

			By("Deleting the endpoint")
			Expect(k8sClient.Delete(ctx, createdEndpoint)).Should(Succeed())
		})
	})
})

func newCert(certName, certNamespace string) *certificatev1alpha1.Certificate {
	return &certificatev1alpha1.Certificate{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "acm-manager/v1alpha1",
			Kind:       "Certificate",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name:      certName,
			Namespace: certNamespace,
		},
		Spec: certificatev1alpha1.CertificateSpec{
			CommonName:              "test.local",
			SubjectAlternativeNames: []string{"test.local"},
		},
	}
}
