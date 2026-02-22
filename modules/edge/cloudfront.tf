# ═══════════════════════════════════════════════════════════
# CLOUDFRONT — CDN con WAF, cache per static assets
# ═══════════════════════════════════════════════════════════

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.name_prefix} dashboard distribution"
  default_root_object = ""
  price_class         = "PriceClass_100" # US, Canada, Europe — ottimizzare costi
  web_acl_id          = var.waf_web_acl_arn
  aliases             = [var.domain_name]

  # ── Origin: ALB (API + Dynamic Content) ───────────────
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Header custom per verificare che le richieste arrivino da CF
    custom_header {
      name  = "X-Custom-Origin-Verify"
      value = "acme-cf-secret-2024" # In produzione, usare un valore da Secrets Manager
    }
  }

  # ── Default Behavior (API + Dynamic) ──────────────────
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-origin"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    # Non cachare contenuti dinamici
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # ── Behavior per static assets (cachato) ──────────────
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-origin"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

    min_ttl     = 0
    default_ttl = 86400    # 1 giorno
    max_ttl     = 31536000 # 1 anno
  }

  # ── Behavior per assets con hash (aggressive caching) ─
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "alb-origin"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

    min_ttl     = 0
    default_ttl = 604800   # 7 giorni
    max_ttl     = 31536000 # 1 anno
  }

  # ── TLS ───────────────────────────────────────────────
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # ── Geo Restriction ──────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none" # Nessuna restrizione geografica
    }
  }

  # ── Custom Error Responses ───────────────────────────
  custom_error_response {
    error_code         = 503
    response_code      = 503
    response_page_path = "/error/503.html"
  }

  tags = {
    Name = "${var.name_prefix}-cloudfront"
  }

  depends_on = [aws_acm_certificate_validation.cloudfront]
}

# ── Data Sources per Cache Policies ─────────────────────
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}