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

// Code generated by applyconfiguration-gen. DO NOT EDIT.

package applyconfiguration

import (
	v1alpha1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
	acmmanagerv1alpha1 "vdesjardins/acm-manager/pkg/client/applyconfiguration/acmmanager/v1alpha1"

	schema "k8s.io/apimachinery/pkg/runtime/schema"
)

// ForKind returns an apply configuration type for the given GroupVersionKind, or nil if no
// apply configuration type exists for the given GroupVersionKind.
func ForKind(kind schema.GroupVersionKind) interface{} {
	switch kind {
	// Group=acm-manager.io, Version=v1alpha1
	case v1alpha1.SchemeGroupVersion.WithKind("Certificate"):
		return &acmmanagerv1alpha1.CertificateApplyConfiguration{}
	case v1alpha1.SchemeGroupVersion.WithKind("CertificateSpec"):
		return &acmmanagerv1alpha1.CertificateSpecApplyConfiguration{}
	case v1alpha1.SchemeGroupVersion.WithKind("CertificateStatus"):
		return &acmmanagerv1alpha1.CertificateStatusApplyConfiguration{}
	case v1alpha1.SchemeGroupVersion.WithKind("ResourceRecord"):
		return &acmmanagerv1alpha1.ResourceRecordApplyConfiguration{}

	}
	return nil
}
