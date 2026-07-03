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
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/prometheus/client_golang/prometheus/testutil"

	certificatev1alpha1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
)

var _ = Describe("Metrics", func() {
	const (
		certName      = "metrics-test-cert"
		certNamespace = "default"
		commonName    = "example.com"
	)

	AfterEach(func() {
		// Clean up metrics after each test to prevent cross-contamination
		DeleteCertificateMetrics(certName, certNamespace)
	})

	Describe("RecordCertificateStatus", func() {
		It("should set gauge to 1 for the current status and 0 for all others", func() {
			RecordCertificateStatus(certName, certNamespace, commonName, certificatev1alpha1.CertificateStatusIssued)

			// Issued should be 1
			val := testutil.ToFloat64(certificateStatus.WithLabelValues(certName, certNamespace, commonName, string(certificatev1alpha1.CertificateStatusIssued)))
			Expect(val).To(Equal(float64(1)))

			// All others should be 0
			for _, s := range allStatuses {
				if s == certificatev1alpha1.CertificateStatusIssued {
					continue
				}
				val := testutil.ToFloat64(certificateStatus.WithLabelValues(certName, certNamespace, commonName, string(s)))
				Expect(val).To(Equal(float64(0)), "expected status %s to be 0", s)
			}
		})

		It("should update gauge when status changes", func() {
			RecordCertificateStatus(certName, certNamespace, commonName, certificatev1alpha1.CertificateStatusIssued)
			RecordCertificateStatus(certName, certNamespace, commonName, certificatev1alpha1.CertificateStatusExpired)

			// Issued should now be 0
			val := testutil.ToFloat64(certificateStatus.WithLabelValues(certName, certNamespace, commonName, string(certificatev1alpha1.CertificateStatusIssued)))
			Expect(val).To(Equal(float64(0)))

			// Expired should be 1
			val = testutil.ToFloat64(certificateStatus.WithLabelValues(certName, certNamespace, commonName, string(certificatev1alpha1.CertificateStatusExpired)))
			Expect(val).To(Equal(float64(1)))
		})

		It("should correctly report failure states", func() {
			failureStates := []certificatev1alpha1.CertificateStatusType{
				certificatev1alpha1.CertificateStatusFailed,
				certificatev1alpha1.CertificateStatusValidationTimedOut,
				certificatev1alpha1.CertificateStatusError,
				certificatev1alpha1.CertificateStatusExpired,
				certificatev1alpha1.CertificateStatusRevoked,
			}

			for _, failStatus := range failureStates {
				RecordCertificateStatus(certName, certNamespace, commonName, failStatus)
				val := testutil.ToFloat64(certificateStatus.WithLabelValues(certName, certNamespace, commonName, string(failStatus)))
				Expect(val).To(Equal(float64(1)), "expected status %s to be 1", failStatus)
			}
		})
	})

	Describe("RecordCertificateExpiry", func() {
		It("should set expiry time as unix timestamp", func() {
			expiryTime := time.Date(2025, 12, 31, 23, 59, 59, 0, time.UTC)
			RecordCertificateExpiry(certName, certNamespace, commonName, expiryTime)

			val := testutil.ToFloat64(certificateExpiryTime.WithLabelValues(certName, certNamespace, commonName))
			Expect(val).To(Equal(float64(expiryTime.Unix())))
		})

		It("should update expiry time when called again", func() {
			firstExpiry := time.Date(2025, 6, 15, 0, 0, 0, 0, time.UTC)
			secondExpiry := time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC)

			RecordCertificateExpiry(certName, certNamespace, commonName, firstExpiry)
			RecordCertificateExpiry(certName, certNamespace, commonName, secondExpiry)

			val := testutil.ToFloat64(certificateExpiryTime.WithLabelValues(certName, certNamespace, commonName))
			Expect(val).To(Equal(float64(secondExpiry.Unix())))
		})
	})

	Describe("RecordCertificateError", func() {
		It("should increment the error counter", func() {
			before := testutil.ToFloat64(certificateRequestErrors.WithLabelValues(certName, certNamespace, "request"))

			RecordCertificateError(certName, certNamespace, "request")
			RecordCertificateError(certName, certNamespace, "request")

			after := testutil.ToFloat64(certificateRequestErrors.WithLabelValues(certName, certNamespace, "request"))
			Expect(after - before).To(Equal(float64(2)))
		})

		It("should track different operations independently", func() {
			beforeRequest := testutil.ToFloat64(certificateRequestErrors.WithLabelValues(certName, certNamespace, "request"))
			beforeDescribe := testutil.ToFloat64(certificateRequestErrors.WithLabelValues(certName, certNamespace, "describe"))

			RecordCertificateError(certName, certNamespace, "request")
			RecordCertificateError(certName, certNamespace, "describe")
			RecordCertificateError(certName, certNamespace, "describe")

			afterRequest := testutil.ToFloat64(certificateRequestErrors.WithLabelValues(certName, certNamespace, "request"))
			afterDescribe := testutil.ToFloat64(certificateRequestErrors.WithLabelValues(certName, certNamespace, "describe"))

			Expect(afterRequest - beforeRequest).To(Equal(float64(1)))
			Expect(afterDescribe - beforeDescribe).To(Equal(float64(2)))
		})
	})

	Describe("RecordStatusTransition", func() {
		It("should increment counter on status change", func() {
			from := certificatev1alpha1.CertificateStatusIssued
			to := certificatev1alpha1.CertificateStatusExpired

			before := testutil.ToFloat64(certificateStatusTransitions.WithLabelValues(certName, certNamespace, string(from), string(to)))

			RecordStatusTransition(certName, certNamespace, from, to)

			after := testutil.ToFloat64(certificateStatusTransitions.WithLabelValues(certName, certNamespace, string(from), string(to)))
			Expect(after - before).To(Equal(float64(1)))
		})

		It("should not increment counter when status is unchanged", func() {
			status := certificatev1alpha1.CertificateStatusIssued

			before := testutil.ToFloat64(certificateStatusTransitions.WithLabelValues(certName, certNamespace, string(status), string(status)))

			RecordStatusTransition(certName, certNamespace, status, status)

			after := testutil.ToFloat64(certificateStatusTransitions.WithLabelValues(certName, certNamespace, string(status), string(status)))
			Expect(after - before).To(Equal(float64(0)))
		})

		It("should handle transition from empty status (initial)", func() {
			from := certificatev1alpha1.CertificateStatusType("")
			to := certificatev1alpha1.CertificateStatusRequested

			before := testutil.ToFloat64(certificateStatusTransitions.WithLabelValues(certName, certNamespace, string(from), string(to)))

			RecordStatusTransition(certName, certNamespace, from, to)

			after := testutil.ToFloat64(certificateStatusTransitions.WithLabelValues(certName, certNamespace, string(from), string(to)))
			Expect(after - before).To(Equal(float64(1)))
		})
	})

	Describe("DeleteCertificateMetrics", func() {
		It("should remove all metric series for a certificate", func() {
			// Set up some metrics
			RecordCertificateStatus(certName, certNamespace, commonName, certificatev1alpha1.CertificateStatusIssued)
			RecordCertificateExpiry(certName, certNamespace, commonName, time.Now().Add(24*time.Hour))
			RecordCertificateError(certName, certNamespace, "request")

			// Verify metrics exist
			val := testutil.ToFloat64(certificateStatus.WithLabelValues(certName, certNamespace, commonName, string(certificatev1alpha1.CertificateStatusIssued)))
			Expect(val).To(Equal(float64(1)))

			// Delete metrics
			DeleteCertificateMetrics(certName, certNamespace)

			// Verify status gauge is reset (will return 0 for a non-existent series)
			val = testutil.ToFloat64(certificateStatus.WithLabelValues(certName, certNamespace, commonName, string(certificatev1alpha1.CertificateStatusIssued)))
			Expect(val).To(Equal(float64(0)))
		})
	})
})
