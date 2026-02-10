package controllers

import (
	"context"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/acm"
	acmtypes "github.com/aws/aws-sdk-go-v2/service/acm/types"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"

	apiV1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
	"vdesjardins/acm-manager/pkg/controllers/external_api_clients"
)

type acmClientCleanupMock struct {
	deleteCalled bool
}

type certificateClientCleanupMock struct {
	getCalled bool
}

func (c *certificateClientCleanupMock) GetCertificateForNamespace(ctx context.Context, namespace string, certificateName string, options metav1.GetOptions) (*apiV1.Certificate, error) {
	c.getCalled = true

	return nil, errors.NewNotFound(schema.GroupResource{Group: "unit-test.com", Resource: "unit-test"},
		"unit-test")
}

func (a *acmClientCleanupMock) DescribeCertificate(ctx context.Context, params *acm.DescribeCertificateInput, optFns ...func(*acm.Options)) (*acm.DescribeCertificateOutput, error) {
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

func (a *acmClientCleanupMock) RequestCertificate(ctx context.Context, params *acm.RequestCertificateInput, optFns ...func(*acm.Options)) (*acm.RequestCertificateOutput, error) {
	return &acm.RequestCertificateOutput{
		CertificateArn: aws.String("test-arn"),
	}, nil
}

func (a *acmClientCleanupMock) DeleteCertificate(ctx context.Context, params *acm.DeleteCertificateInput, optFns ...func(*acm.Options)) (*acm.DeleteCertificateOutput, error) {
	a.deleteCalled = true
	return nil, nil
}

func (a *acmClientCleanupMock) ListCertificates(ctx context.Context, params *acm.ListCertificatesInput, optFns ...func(*acm.Options)) (*acm.ListCertificatesOutput, error) {
	return &acm.ListCertificatesOutput{
		CertificateSummaryList: []acmtypes.CertificateSummary{
			{
				CertificateArn: aws.String("test-arn"),
			},
		},
	}, nil
}

func (a *acmClientCleanupMock) ListTagsForCertificate(ctx context.Context, params *acm.ListTagsForCertificateInput, optFns ...func(*acm.Options)) (*acm.ListTagsForCertificateOutput, error) {
	return &acm.ListTagsForCertificateOutput{
		Tags: []acmtypes.Tag{
			{
				Key:   aws.String(TagCertificateName),
				Value: aws.String("test-arn"),
			},
			{
				Key:   aws.String(TagCertificateNamespace),
				Value: aws.String("default"),
			},
			{
				Key:   aws.String(TagCertificateOwner),
				Value: aws.String(ACMManagerOwnerName),
			},
		},
	}, nil
}

var _ = Describe("ACM Certificate Cleanup Job", func() {
	Context("clean missing certificate", func() {
		defer GinkgoRecover()

		acmClientMock := acmClientCleanupMock{}
		Expect(acmClientMock.deleteCalled).To(BeFalse())

		oldACMClient := external_api_clients.NewAcmClient
		external_api_clients.NewAcmClient = func(service *acm.Client) external_api_clients.AcmAWSAPI {
			return &acmClientMock
		}
		defer func() { external_api_clients.NewAcmClient = oldACMClient }()

		certificateClientMock := certificateClientCleanupMock{}
		Expect(certificateClientMock.getCalled).To(BeFalse())
		oldCertificateRestClient := external_api_clients.NewCertificateRestClient
		external_api_clients.NewCertificateRestClient = func(ctx context.Context) (external_api_clients.CertificateRestAPI, error) {
			return &certificateClientMock, nil
		}
		defer func() { external_api_clients.NewCertificateRestClient = oldCertificateRestClient }()

		cleanupOrphanACMCertificates()
		Expect(acmClientMock.deleteCalled).To(BeTrue())
		Expect(certificateClientMock.getCalled).To(BeTrue())
	})
})
