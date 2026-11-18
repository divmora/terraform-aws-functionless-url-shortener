#!/usr/bin/env python3
"""Render the SAM repo's api.yaml into templates/api.yaml.tftpl.

The SAM template embeds api.yaml through AWS::Include, so it uses CloudFormation
intrinsics (Fn::Sub, Fn::GetAtt, Fn::If, Ref). This script replaces each one with a
Terraform templatefile() placeholder. It is strict: any intrinsic or Sub variable it
does not know about is an error, so drift between the two repos fails CI instead of
silently producing a different API.

Usage:
  render_api_template.py <path/to/sam/api.yaml> [output]      # write template
  render_api_template.py --check <path/to/sam/api.yaml>       # exit 1 if out of date
"""
import re
import sys
from pathlib import Path

import yaml

OUTPUT = Path(__file__).resolve().parent.parent / "templates" / "api.yaml.tftpl"

HEADER = """\
# GENERATED FILE - DO NOT EDIT.
# Rendered from api.yaml in https://github.com/divmora/functionless-url-shortener
# by scripts/render_api_template.py. Change the SAM api.yaml, then re-run the script.
#
# templatefile() variables: api_name, region, table_name, read_role_arn,
# crud_role_arn, default_link_ttl_seconds, short_url_prefix
"""

# CloudFormation Sub variable -> Terraform template placeholder.
SUB_VARS = {
    "AWS::Region": "${region}",
    "LinkTable": "${table_name}",
    "TTL": "${default_link_ttl_seconds}",
    "shortUrlPrefix": "${short_url_prefix}",
}
GETATT = {
    ("DDBReadRole", "Arn"): "${read_role_arn}",
    ("DDBCrudRole", "Arn"): "${crud_role_arn}",
}
# The only Sub variable map api.yaml uses: shortUrlPrefix. Terraform computes it instead
# (url_prefix, else https://<domain_alias>, else empty), mirroring the SAM Fn::If chain.
ALLOWED_SUB_VAR_MAPS = {"shortUrlPrefix"}


class RenderError(Exception):
    pass


def escape_template(s):
    """Escape sequences that templatefile() would otherwise interpret."""
    return s.replace("${", "$${").replace("%{", "%%{")


def render_sub(template, path):
    if template == "${AWS::StackName}-api":
        return "${api_name}"
    out, pos = [], 0
    for m in re.finditer(r"\$\{([^}]*)\}", template):
        out.append(escape_template(template[pos:m.start()]))
        name = m.group(1)
        repl = SUB_VARS.get(name)
        if repl is None:
            raise RenderError(f"{path}: unsupported Fn::Sub variable ${{{name}}}")
        out.append(repl)
        pos = m.end()
    out.append(escape_template(template[pos:]))
    return "".join(out)


def convert(node, path="$"):
    if isinstance(node, dict):
        if len(node) == 1:
            ((key, value),) = node.items()
            if key == "Fn::Sub":
                if isinstance(value, str):
                    return render_sub(value, path)
                template, variables = value
                if set(variables) - ALLOWED_SUB_VAR_MAPS:
                    raise RenderError(f"{path}: unsupported Fn::Sub variable map {sorted(variables)}")
                return render_sub(template, path)
            if key == "Fn::GetAtt":
                repl = GETATT.get(tuple(value))
                if repl is None:
                    raise RenderError(f"{path}: unsupported Fn::GetAtt {value}")
                return repl
            if key.startswith("Fn::") or key == "Ref":
                raise RenderError(f"{path}: unsupported intrinsic {key}")
        return {k: convert(v, f"{path}.{k}") for k, v in node.items()}
    if isinstance(node, list):
        return [convert(v, f"{path}[{i}]") for i, v in enumerate(node)]
    if isinstance(node, str):
        return escape_template(node)
    return node


def render(source):
    spec = yaml.safe_load(Path(source).read_text())
    body = yaml.safe_dump(convert(spec), sort_keys=False, width=100000, allow_unicode=True)
    return HEADER + body


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if not args:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        rendered = render(args[0])
    except RenderError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    out = Path(args[1]) if len(args) > 1 else OUTPUT
    if check:
        if not out.exists() or out.read_text() != rendered:
            print(f"{out} is out of date with {args[0]}; run scripts/render_api_template.py", file=sys.stderr)
            return 1
        print(f"{out} is up to date")
        return 0
    out.write_text(rendered)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
