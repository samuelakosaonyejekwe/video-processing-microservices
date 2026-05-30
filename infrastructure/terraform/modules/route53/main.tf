resource "aws_route53_zone" "primary" {

  name = var.hosted_zone_name

  tags = var.tags
}

resource "aws_route53_record" "gateway" {

  zone_id = aws_route53_zone.primary.zone_id

  name = var.domain_name

  type = "A"

  alias {

    name = var.alb_dns_name

    zone_id = var.alb_zone_id

    evaluate_target_health = true
  }
}