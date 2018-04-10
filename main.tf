provider "aws" {
  alias = "def"
}

provider "aws" {
  alias = "dst"
}

module "origin_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.1"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  delimiter  = "${var.delimiter}"
  attributes = ["${compact(concat(var.attributes, list("origin")))}"]
  tags       = "${var.tags}"
}

resource "aws_cloudfront_origin_access_identity" "default" {
  comment = "${module.distribution_label.id}"
}

module "distribution_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.1"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  attributes = "${var.attributes}"
  delimiter  = "${var.delimiter}"
  tags       = "${var.tags}"
}

resource "aws_cloudfront_distribution" "default" {
  enabled             = "${var.enabled}"
  is_ipv6_enabled     = "${var.is_ipv6_enabled}"
  comment             = "${var.comment}"
  default_root_object = "${var.default_root_object}"
  price_class         = "${var.price_class}"
  http_version        = "${var.http_version}"

  logging_config = {
    include_cookies = "${var.log_include_cookies}"
    bucket          = "${var.log_bucket}"
    prefix          = "${var.log_prefix}"
  }

  aliases = ["${var.aliases}"]

  custom_error_response = ["${var.custom_error_response}"]

  origin {
    domain_name = "${var.origin_domain_name}"
    origin_id   = "${module.distribution_label.id}"
    origin_path = "${var.origin_path}"

    custom_origin_config {
      http_port                = "${var.origin_http_port}"
      https_port               = "${var.origin_https_port}"
      origin_protocol_policy   = "${var.origin_protocol_policy}"
      origin_ssl_protocols     = "${var.origin_ssl_protocols}"
      origin_keepalive_timeout = "${var.origin_keepalive_timeout}"
      origin_read_timeout      = "${var.origin_read_timeout}"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = "${var.acm_certificate_arn == "" ? join(" ",aws_acm_certificate_validation.cert.*.certificate_arn) : var.acm_certificate_arn}"
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1"
    cloudfront_default_certificate = "${var.acm_certificate_arn == "" ? true : false}"
  }

  default_cache_behavior {
    allowed_methods  = "${var.allowed_methods}"
    cached_methods   = "${var.cached_methods}"
    target_origin_id = "${module.distribution_label.id}"
    compress         = "${var.compress}"

    forwarded_values {
      headers = ["${var.forward_headers}"]

      query_string = "${var.forward_query_string}"
      query_string_cache_keys = "${var.query_string_cache_keys}"

      cookies {
        forward           = "${var.forward_cookies}"
        whitelisted_names = ["${var.forward_cookies_whitelisted_names}"]
      }
    }

    viewer_protocol_policy = "${var.viewer_protocol_policy}"

    lambda_function_association {
      event_type = "${var.lambda_event_trigger_type}"
      lambda_arn = "${var.lambda_arn}"
    }
  }

  cache_behavior = "${var.cache_behavior}"

  restrictions {
    geo_restriction {
      restriction_type = "${var.geo_restriction_type}"
      locations        = "${var.geo_restriction_locations}"
    }
  }



  tags = "${module.distribution_label.tags}"
}

resource "aws_acm_certificate" "cert" {
  count = "${var.acm_certificate_arn == "" ? 1 : 0}"
  provider = "aws.dst"
  domain_name = "${var.aliases[0]}"
  subject_alternative_names = "${compact(split(",", replace(join(",",var.aliases), var.aliases[0], "")))}"
  validation_method = "DNS"
}

data "aws_route53_zone" "zone" {
  count = "${var.acm_certificate_arn == "" ? 1 : 0}"
  name = "${var.parent_zone_name}"
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  count = "${var.acm_certificate_arn == "" ? length(var.aliases) : 0}"
  name = "${lookup(aws_acm_certificate.cert.domain_validation_options[count.index], "resource_record_name")}"
  type = "${lookup(aws_acm_certificate.cert.domain_validation_options[count.index], "resource_record_type")}"
  zone_id = "${data.aws_route53_zone.zone.id}"
  records = ["${lookup(aws_acm_certificate.cert.domain_validation_options[count.index], "resource_record_value")}"]
  ttl = 60
}

resource "aws_acm_certificate_validation" "cert" {
  count = "${var.acm_certificate_arn == "" ? 1 : 0}"
  provider = "aws.dst"
  certificate_arn = "${aws_acm_certificate.cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.cert_validation.*.fqdn}"]
}
