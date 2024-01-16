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

package main

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	// Import all Kubernetes client auth plugins (e.g. Azure, GCP, OIDC, etc.)
	// to ensure that exec-entrypoint and run can make use of them.
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	certificatev1alpha1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
	clientv1alpha1 "vdesjardins/acm-manager/pkg/clientset/v1alpha1"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

var (
	clientset  *kubernetes.Clientset
	certClient *clientv1alpha1.Client
	domainName string
)

const (
	TestKubeConfig = "TEST_KUBECONFIG_LOCATION"
	TestDomainName = "TEST_DOMAIN_NAME"
)

func TestMain(m *testing.M) {
	domainName = os.Getenv(TestDomainName)
	if domainName == "" {
		panic(fmt.Errorf("variable %s not set", TestDomainName))
	}

	kubeConfig := os.Getenv(TestKubeConfig)
	if kubeConfig == "" {
		panic(fmt.Errorf("variable %s not set", TestKubeConfig))
	}

	clientConfig, err := clientcmd.BuildConfigFromFlags("", kubeConfig)
	if err != nil {
		panic(err.Error())
	}

	clientset, err = kubernetes.NewForConfig(clientConfig)
	if err != nil {
		panic(err.Error())
	}

	certClient, err = clientv1alpha1.NewForConfig(clientConfig)
	if err != nil {
		panic(err.Error())
	}

	exitTest := m.Run()

	os.Exit(exitTest)
}

func TestCertificate(t *testing.T) {
	ctx := context.TODO()
	ns := "default"

	certTests := []struct {
		cert   certificatev1alpha1.Certificate
		status certificatev1alpha1.CertificateStatusType
	}{
		{
			cert: certificatev1alpha1.Certificate{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-1",
					Namespace: ns,
				},
				Spec: certificatev1alpha1.CertificateSpec{
					CommonName: "test1." + domainName,
					SubjectAlternativeNames: []string{
						"test1." + domainName,
					},
				},
			},
			status: certificatev1alpha1.CertificateStatusIssued,
		},
	}

	for _, certTest := range certTests {
		func() {
			cert := certTest.cert
			certName := cert.GetName()
			_, err := certClient.Certificates(ns).Create(ctx, &cert, metav1.CreateOptions{})
			if err != nil {
				t.Errorf("unable to create certificate: %s", err.Error())
			}

			// delete certificate
			defer func() {
				err = certClient.Certificates(ns).Delete(ctx, certName, metav1.DeleteOptions{})
				if err != nil {
					t.Errorf("error deleting certificate: %s", err.Error())
				}

				// check if certificate is deleted in AWS
				// TODO
			}()

			// wait for issuance
			err = waitForCertificateStatus(ctx, certClient, certName, ns, certTest.status)
			if err != nil {
				t.Errorf("error waiting for certificate readiness: %s", err.Error())
			}
		}()
	}
}

func TestCertificateChange(t *testing.T) {
	ctx := context.TODO()
	ns := "default"

	cert := &certificatev1alpha1.Certificate{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "test-change-1",
			Namespace: ns,
		},
		Spec: certificatev1alpha1.CertificateSpec{
			CommonName: "test1." + domainName,
			SubjectAlternativeNames: []string{
				"test1." + domainName,
			},
		},
	}

	_, err := certClient.Certificates(ns).Create(ctx, cert, metav1.CreateOptions{})
	if err != nil {
		t.Errorf("unable to create certificate: %s", err.Error())
	}

	defer func() {
		// delete certificate
		err = certClient.Certificates(ns).Delete(ctx, cert.Name, metav1.DeleteOptions{})
		if err != nil {
			t.Errorf("error deleting certificate: %s", err.Error())
		}

		// check if certificate is deleted in AWS
		// TODO
	}()

	// wait for issuance
	err = waitForCertificateStatus(ctx, certClient, cert.Name, ns, certificatev1alpha1.CertificateStatusIssued)
	if err != nil {
		t.Errorf("error waiting for certificate readiness: %s", err.Error())
	}

	// change dns names
	cert, err = certClient.Certificates(ns).Get(ctx, cert.Name, metav1.GetOptions{})
	if err != nil {
		t.Errorf("unable to get certificate: %s", err.Error())
	}
	cert.Spec.SubjectAlternativeNames = append(cert.Spec.SubjectAlternativeNames, "test2."+domainName)
	_, err = certClient.Certificates(ns).Update(ctx, cert, metav1.UpdateOptions{})
	if err != nil {
		t.Errorf("unable to update certificate: %s", err.Error())
	}

	// wait for pending status
	err = waitForCertificateStatus(ctx, certClient, cert.Name, ns, certificatev1alpha1.CertificateStatusPendingValidation)
	if err != nil {
		t.Errorf("error waiting for certificate readiness: %s", err.Error())
	}

	// wait for issuance
	err = waitForCertificateStatus(ctx, certClient, cert.Name, ns, certificatev1alpha1.CertificateStatusIssued)
	if err != nil {
		t.Errorf("error waiting for certificate readiness: %s", err.Error())
	}
}

// TODO: test ingress
func waitForCertificateStatus(ctx context.Context, certClient *clientv1alpha1.Client, certName, ns string, status certificatev1alpha1.CertificateStatusType) error {
	return wait.PollImmediate(250*time.Millisecond, 5*time.Minute,
		func() (bool, error) {
			cert, err := certClient.Certificates(ns).Get(ctx, certName, metav1.GetOptions{})
			if err != nil {
				return false, fmt.Errorf("error getting certificate: %s", err.Error())
			}

			if cert.Status.Status == status {
				return true, nil
			}

			return false, nil
		})
}
