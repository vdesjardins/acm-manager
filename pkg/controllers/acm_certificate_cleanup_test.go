package controllers

import (
	"context"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/acm"
	acmtypes "github.com/aws/aws-sdk-go-v2/service/acm/types"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

type acmClientCleanupMock struct {
	deleteCalled bool
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

		if os.Getenv("GITHUB_RUN_ID") != "" {
			// Skipping test when running on GITHUB, because of external dependency to a running K8S API
			return
		}

		mock := acmClientCleanupMock{}
		Expect(mock.deleteCalled).To(BeFalse())

		oldClient := newAcmClient
		newAcmClient = func(service *acm.Client) acmAPI {
			return &mock
		}
		defer func() { newAcmClient = oldClient }()

		cleanupOrphanACMCertificates()
		Expect(mock.deleteCalled).To(BeTrue())
	})
})
