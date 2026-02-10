package external_api_clients

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/service/acm"
)

type acmClient struct {
	svc *acm.Client
}

type AcmAWSAPI interface {
	DescribeCertificate(ctx context.Context, params *acm.DescribeCertificateInput, optFns ...func(*acm.Options)) (*acm.DescribeCertificateOutput, error)
	RequestCertificate(ctx context.Context, params *acm.RequestCertificateInput, optFns ...func(*acm.Options)) (*acm.RequestCertificateOutput, error)
	DeleteCertificate(ctx context.Context, params *acm.DeleteCertificateInput, optFns ...func(*acm.Options)) (*acm.DeleteCertificateOutput, error)
	ListCertificates(ctx context.Context, params *acm.ListCertificatesInput, optFns ...func(*acm.Options)) (*acm.ListCertificatesOutput, error)
	ListTagsForCertificate(ctx context.Context, params *acm.ListTagsForCertificateInput, optFns ...func(*acm.Options)) (*acm.ListTagsForCertificateOutput, error)
}

var NewAcmClient = func(service *acm.Client) AcmAWSAPI {
	return &acmClient{svc: service}
}

func (a *acmClient) DescribeCertificate(ctx context.Context, params *acm.DescribeCertificateInput, optFns ...func(*acm.Options)) (*acm.DescribeCertificateOutput, error) {
	return a.svc.DescribeCertificate(ctx, params, optFns...)
}

func (a *acmClient) RequestCertificate(ctx context.Context, params *acm.RequestCertificateInput, optFns ...func(*acm.Options)) (*acm.RequestCertificateOutput, error) {
	return a.svc.RequestCertificate(ctx, params, optFns...)
}

func (a *acmClient) DeleteCertificate(ctx context.Context, params *acm.DeleteCertificateInput, optFns ...func(*acm.Options)) (*acm.DeleteCertificateOutput, error) {
	return a.svc.DeleteCertificate(ctx, params, optFns...)
}

func (a *acmClient) ListCertificates(ctx context.Context, params *acm.ListCertificatesInput, optFns ...func(*acm.Options)) (*acm.ListCertificatesOutput, error) {
	return a.svc.ListCertificates(ctx, params)
}

func (a *acmClient) ListTagsForCertificate(ctx context.Context, params *acm.ListTagsForCertificateInput, optFns ...func(*acm.Options)) (*acm.ListTagsForCertificateOutput, error) {
	return a.svc.ListTagsForCertificate(ctx, params)
}
