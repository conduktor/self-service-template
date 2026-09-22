#!/usr/bin/env python3
"""Render policy-checkable Conduktor manifests from a Terraform plan.

`terraform plan` is client-side: it diffs config against state and never asks
Console whether a resource would be accepted. Conduktor evaluates ResourcePolicy
CEL rules server-side on write, so a policy violation does not surface until
`terraform apply` -- by which point the PR is already merged.

This script bridges that gap. It extracts the resources that ResourcePolicies
can target from a plan and emits Conduktor manifests, so the PR job can run
`conduktor apply --dry-run` and get a real server-side verdict before merge.

Only the four policy-targetable kinds are handled (Topic, Subject, Connector,
ApplicationGroup); everything else in the plan is ignored. Only create/update
actions are emitted -- policies do not apply to deletes.

Output is a multi-document YAML stream. Each document is JSON, which is valid
YAML, so this has no third-party dependencies.

Usage:
    terraform show -json tfplan > plan.json
    scripts/plan-to-manifests.py plan.json > manifests.yml
    conduktor apply -f manifests.yml --dry-run
"""

import json
import sys


def _drop_empty(d):
    """Strip keys whose value is None or an empty dict/list.

    Unknown ("known after apply") values arrive as None. Emitting them would
    make the dry-run reject a resource for the wrong reason, so they are
    omitted and left to Console's own defaulting.
    """
    return {k: v for k, v in d.items() if v is not None and v != {} and v != []}


def topic(v):
    spec = v.get("spec") or {}
    return {
        "apiVersion": "kafka/v2",
        "kind": "Topic",
        "metadata": _drop_empty({
            "cluster": v.get("cluster"),
            "name": v.get("name"),
            "labels": v.get("labels"),
        }),
        "spec": _drop_empty({
            "replicationFactor": spec.get("replication_factor"),
            "partitions": spec.get("partitions"),
            "configs": spec.get("configs"),
        }),
    }


def subject(v):
    spec = v.get("spec") or {}
    refs = [
        {"name": r.get("name"), "subject": r.get("subject"), "version": r.get("version")}
        for r in (spec.get("references") or [])
    ]
    return {
        "apiVersion": "kafka/v2",
        "kind": "Subject",
        "metadata": _drop_empty({
            "cluster": v.get("cluster"),
            "name": v.get("name"),
            "labels": v.get("labels"),
        }),
        "spec": _drop_empty({
            "format": spec.get("format"),
            "compatibility": spec.get("compatibility"),
            "schema": spec.get("schema"),
            "references": refs,
        }),
    }


def connector(v):
    spec = v.get("spec") or {}
    return {
        "apiVersion": "kafka/v2",
        "kind": "Connector",
        "metadata": _drop_empty({
            "cluster": v.get("cluster"),
            "connectCluster": v.get("connect_cluster"),
            "name": v.get("name"),
            "labels": v.get("labels"),
        }),
        "spec": _drop_empty({
            "config": spec.get("config"),
            "initialState": spec.get("initial_state"),
        }),
    }


def application_group(v):
    spec = v.get("spec") or {}
    perms = [
        _drop_empty({
            "appInstance": p.get("app_instance"),
            "resourceType": p.get("resource_type"),
            "patternType": p.get("pattern_type"),
            "connectCluster": p.get("connect_cluster"),
            "name": p.get("name"),
            "permissions": p.get("permissions"),
        })
        for p in (spec.get("permissions") or [])
    ]
    # appgroup-restrictions checks `spec.members`, so members must be emitted
    # even when empty -- _drop_empty would remove it and change the verdict.
    body = _drop_empty({
        "displayName": spec.get("display_name"),
        "description": spec.get("description"),
        "externalGroups": spec.get("external_groups"),
        "permissions": perms,
    })
    body["members"] = spec.get("members") or []
    return {
        "apiVersion": "self-serve/v1",
        "kind": "ApplicationGroup",
        "metadata": _drop_empty({
            "application": v.get("application"),
            "name": v.get("name"),
        }),
        "spec": body,
    }


HANDLERS = {
    "conduktor_console_topic_v2": topic,
    "conduktor_console_kafka_subject_v2": subject,
    "conduktor_console_connector_v2": connector,
    "conduktor_console_application_group_v1": application_group,
}


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as f:
            plan = json.load(f)
    else:
        plan = json.load(sys.stdin)

    docs = []
    for change in plan.get("resource_changes") or []:
        handler = HANDLERS.get(change.get("type"))
        if handler is None:
            continue
        actions = (change.get("change") or {}).get("actions") or []
        if not ({"create", "update"} & set(actions)):
            continue
        after = (change.get("change") or {}).get("after")
        if after is None:
            continue
        docs.append(handler(after))

    if not docs:
        print(
            "No policy-targetable resources in plan; nothing to dry-run.",
            file=sys.stderr,
        )
        return

    for doc in docs:
        print("---")
        print(json.dumps(doc, indent=2, sort_keys=False))

    print(f"Rendered {len(docs)} manifest(s) for dry-run.", file=sys.stderr)


if __name__ == "__main__":
    main()
