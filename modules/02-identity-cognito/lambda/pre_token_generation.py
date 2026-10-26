"""
Amazon Cognito Pre-Token Generation Trigger for Claude Apps Gateway.
Injects the user's Cognito User Pool groups into the OIDC token claim `groups`
so the Claude Apps Gateway can map users to group spend quotas and admin roles.
"""


def handler(event, context):
    groups = event.get("request", {}).get("groupConfiguration", {}).get("groupsToOverride", [])
    groups_claim = ",".join(groups) if isinstance(groups, list) else str(groups)

    event["response"] = {
        "claimsOverrideDetails": {
            "claimsToAddOrOverride": {
                "groups": groups_claim
            }
        }
    }
    return event
