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

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

var _ = Describe("Ingress controller", func() {
	const (
		timeout  = time.Second * 30
		interval = time.Millisecond * 250
	)

	Context("When creating Ingress", func() {
		It("Should set certificate arn annotation", func() {
			By("By creating a new Ingress")
			ingName := "test-ingress"
			ingNamespace := "default"

			ctx := context.Background()
			ing := newIngress(ingName, ingNamespace)
			Expect(k8sClient.Create(ctx, ing)).Should(Succeed())

			lookupKey := types.NamespacedName{Name: ingName, Namespace: ingNamespace}
			createdCert := &certificatev1alpha1.Certificate{}

			By("By checking that certificate is created")
			Eventually(func() bool {
				err := k8sClient.Get(ctx, lookupKey, createdCert)
				return err == nil
			}, timeout, interval).Should(BeTrue())

			By("By checking that ingress is updated with certificate arn")
			createdIngress := &networkingv1.Ingress{}
			Eventually(func() bool {
				err := k8sClient.Get(ctx, lookupKey, createdIngress)
				if err != nil {
					return false
				}
				_, ok := createdIngress.GetAnnotations()[IngressCertificateArnKey]
				return ok
			}, timeout, interval).Should(BeTrue())
			Expect(createdIngress.GetAnnotations()[IngressCertificateArnKey]).Should(Equal("test-arn"))

			By("Deleting the ingress")
			Expect(k8sClient.Delete(ctx, createdIngress)).Should(Succeed())

			By("Deleting the certificate")
			Expect(k8sClient.Delete(ctx, createdCert)).Should(Succeed())
		})
	})
})

func newIngress(name, namespace string) *networkingv1.Ingress {
	prefix := networkingv1.PathTypePrefix
	rule := networkingv1.IngressRule{
		Host: "test.local",
		IngressRuleValue: networkingv1.IngressRuleValue{
			HTTP: &networkingv1.HTTPIngressRuleValue{
				Paths: []networkingv1.HTTPIngressPath{
					{
						Path:     "/",
						PathType: &prefix,
						Backend: networkingv1.IngressBackend{
							Service: &networkingv1.IngressServiceBackend{
								Name: "svc",
								Port: networkingv1.ServiceBackendPort{
									Number: 80,
								},
							},
						},
					},
				},
			},
		},
	}
	ingressTLS := networkingv1.IngressTLS{
		Hosts:      []string{"test.local"},
		SecretName: "",
	}

	return &networkingv1.Ingress{
		TypeMeta: metav1.TypeMeta{
			Kind:       "Ingress",
			APIVersion: "networking.k8s.io/v1",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name:        name,
			Namespace:   namespace,
			Annotations: map[string]string{ACMManagerCreateCertificateKey: "true"},
		},
		Spec: networkingv1.IngressSpec{
			Rules: []networkingv1.IngressRule{rule},
			TLS:   []networkingv1.IngressTLS{ingressTLS},
		},
	}
}
