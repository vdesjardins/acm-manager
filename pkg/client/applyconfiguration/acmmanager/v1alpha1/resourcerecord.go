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

package v1alpha1

// ResourceRecordApplyConfiguration represents an declarative configuration of the ResourceRecord type for use
// with apply.
type ResourceRecordApplyConfiguration struct {
	Name  *string `json:"name,omitempty"`
	Type  *string `json:"type,omitempty"`
	Value *string `json:"value,omitempty"`
}

// ResourceRecordApplyConfiguration constructs an declarative configuration of the ResourceRecord type for use with
// apply.
func ResourceRecord() *ResourceRecordApplyConfiguration {
	return &ResourceRecordApplyConfiguration{}
}

// WithName sets the Name field in the declarative configuration to the given value
// and returns the receiver, so that objects can be built by chaining "With" function invocations.
// If called multiple times, the Name field is set to the value of the last call.
func (b *ResourceRecordApplyConfiguration) WithName(value string) *ResourceRecordApplyConfiguration {
	b.Name = &value
	return b
}

// WithType sets the Type field in the declarative configuration to the given value
// and returns the receiver, so that objects can be built by chaining "With" function invocations.
// If called multiple times, the Type field is set to the value of the last call.
func (b *ResourceRecordApplyConfiguration) WithType(value string) *ResourceRecordApplyConfiguration {
	b.Type = &value
	return b
}

// WithValue sets the Value field in the declarative configuration to the given value
// and returns the receiver, so that objects can be built by chaining "With" function invocations.
// If called multiple times, the Value field is set to the value of the last call.
func (b *ResourceRecordApplyConfiguration) WithValue(value string) *ResourceRecordApplyConfiguration {
	b.Value = &value
	return b
}
