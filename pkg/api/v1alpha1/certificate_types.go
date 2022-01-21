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

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type CertificateStatusType string

const (
	CertificateStatusPendingValidation  CertificateStatusType = "PendingValidation"
	CertificateStatusIssued             CertificateStatusType = "Issued"
	CertificateStatusInactive           CertificateStatusType = "Inactive"
	CertificateStatusExpired            CertificateStatusType = "Expired"
	CertificateStatusValidationTimedOut CertificateStatusType = "ValidationTimedOut"
	CertificateStatusRevoked            CertificateStatusType = "Revoked"
	CertificateStatusFailed             CertificateStatusType = "Failed"
	CertificateStatusUnknown            CertificateStatusType = "Unknown"
	CertificateStatusError              CertificateStatusType = "Error"
	CertificateStatusRequested          CertificateStatusType = "Requested"
)

// CertificateSpec defines the desired state of Certificate
type CertificateSpec struct {
	//+kubebuilder:validation:MaxLength=64
	//+kubebuilder:validation:Required
	//+kubebuilder:validation:Pattern=`^(\*\.)?(([A-Za-z0-9-]{0,62}[A-Za-z0-9])\.)+([A-Za-z0-9-]{1,62}[A-Za-z0-9])$`
	// DNS Common Name
	CommonName string `json:"commonName"`

	// DNS Subject Alternative Names
	SubjectAlternativeNames []string `json:"subjectAlternativeNames,omitempty"`
}

// CertificateStatus defines the observed state of Certificate
type CertificateStatus struct {
	// Certificate ARN
	CertificateArn string `json:"certificateArn,omitempty"`

	// Resource Records for DNS validation
	ResourceRecords []ResourceRecord `json:"resourceRecords,omitempty"`

	// Certificate status
	Status CertificateStatusType `json:"status,omitempty"`

	// Certificate not before date
	NotBefore metav1.Time `json:"notBefore,omitempty"`

	// Certificate not after date
	NotAfter metav1.Time `json:"notAfter,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:printcolumn:name="Status",type=string,JSONPath=`.status.status`
//+kubebuilder:printcolumn:name="NotBefore",type=string,JSONPath=`.status.notBefore`
//+kubebuilder:printcolumn:name="NotAfter",type=string,JSONPath=`.status.notAfter`

// Certificate is the Schema for the certificates API
type Certificate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   CertificateSpec   `json:"spec,omitempty"`
	Status CertificateStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// CertificateList contains a list of Certificate
type CertificateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Certificate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Certificate{}, &CertificateList{})
}

type ResourceRecord struct {
	// Name
	Name string `json:"name"`

	// The type of DNS record. Currently this can be CNAME.
	Type string `json:"type"`

	// The value of the CNAME record to add to DNS
	Value string `json:"value"`
}
