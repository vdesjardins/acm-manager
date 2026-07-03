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

	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	certificatev1alpha1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
)

const (
	metricsNamespace = "acm"
	metricsSubsystem = "certificate"
)

// allStatuses lists all possible certificate statuses for gauge reset.
var allStatuses = []certificatev1alpha1.CertificateStatusType{
	certificatev1alpha1.CertificateStatusRequested,
	certificatev1alpha1.CertificateStatusPendingValidation,
	certificatev1alpha1.CertificateStatusIssued,
	certificatev1alpha1.CertificateStatusInactive,
	certificatev1alpha1.CertificateStatusExpired,
	certificatev1alpha1.CertificateStatusValidationTimedOut,
	certificatev1alpha1.CertificateStatusRevoked,
	certificatev1alpha1.CertificateStatusFailed,
	certificatev1alpha1.CertificateStatusUnknown,
	certificatev1alpha1.CertificateStatusError,
}

var (
	certificateStatus = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: metricsNamespace,
			Subsystem: metricsSubsystem,
			Name:      "status",
			Help:      "Current status of ACM certificate. Value is 1 for the active status, 0 for others.",
		},
		[]string{"name", "namespace", "common_name", "status"},
	)

	certificateExpiryTime = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Namespace: metricsNamespace,
			Subsystem: metricsSubsystem,
			Name:      "expiry_time_seconds",
			Help:      "Certificate expiry time as Unix timestamp (seconds). Useful for alerting on upcoming expiry.",
		},
		[]string{"name", "namespace", "common_name"},
	)

	certificateRequestErrors = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Namespace: metricsNamespace,
			Subsystem: metricsSubsystem,
			Name:      "request_errors_total",
			Help:      "Total number of errors encountered during ACM certificate operations.",
		},
		[]string{"name", "namespace", "operation"},
	)

	certificateStatusTransitions = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Namespace: metricsNamespace,
			Subsystem: metricsSubsystem,
			Name:      "status_transitions_total",
			Help:      "Total number of certificate status transitions.",
		},
		[]string{"name", "namespace", "from_status", "to_status"},
	)
)

func init() {
	metrics.Registry.MustRegister(
		certificateStatus,
		certificateExpiryTime,
		certificateRequestErrors,
		certificateStatusTransitions,
	)
}

// RecordCertificateStatus sets the status gauge for a certificate.
// The current status gets value 1, all other statuses get value 0.
func RecordCertificateStatus(name, namespace, commonName string, status certificatev1alpha1.CertificateStatusType) {
	for _, s := range allStatuses {
		val := float64(0)
		if s == status {
			val = 1
		}
		certificateStatus.WithLabelValues(name, namespace, commonName, string(s)).Set(val)
	}
}

// RecordCertificateExpiry sets the expiry time gauge for a certificate.
func RecordCertificateExpiry(name, namespace, commonName string, notAfter time.Time) {
	certificateExpiryTime.WithLabelValues(name, namespace, commonName).Set(float64(notAfter.Unix()))
}

// RecordCertificateError increments the error counter for a certificate operation.
// operation should be one of: "request", "describe", "compare", "update", "delete", "cleanup".
func RecordCertificateError(name, namespace, operation string) {
	certificateRequestErrors.WithLabelValues(name, namespace, operation).Inc()
}

// RecordStatusTransition increments the status transition counter.
func RecordStatusTransition(name, namespace string, fromStatus, toStatus certificatev1alpha1.CertificateStatusType) {
	if fromStatus == toStatus {
		return
	}
	certificateStatusTransitions.WithLabelValues(name, namespace, string(fromStatus), string(toStatus)).Inc()
}

// DeleteCertificateMetrics removes all metric series for a deleted certificate.
// This prevents stale series from lingering after a Certificate CR is removed.
func DeleteCertificateMetrics(name, namespace string) {
	for _, s := range allStatuses {
		certificateStatus.DeleteLabelValues(name, namespace, "", string(s))
	}
	// Also try deleting with partial match for any common_name value
	certificateStatus.DeletePartialMatch(prometheus.Labels{"name": name, "namespace": namespace})
	certificateExpiryTime.DeletePartialMatch(prometheus.Labels{"name": name, "namespace": namespace})
	certificateRequestErrors.DeletePartialMatch(prometheus.Labels{"name": name, "namespace": namespace})
	certificateStatusTransitions.DeletePartialMatch(prometheus.Labels{"name": name, "namespace": namespace})
}
