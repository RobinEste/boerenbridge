"""
Supabase Security Agent

A Claude SDK-powered agent that processes security vulnerability issues
from GitHub and generates SQL migrations to fix them.

Usage:
    python -m security_agent.main --issue-number 123
    python -m security_agent.main --process-all
"""

import os
import sys
import json
import argparse
import logging
from datetime import datetime
from typing import Optional
from dataclasses import dataclass, field

import anthropic
from github import Github, GithubException

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class AgentConfig:
    """Configuration for the security agent."""
    model: str = "claude-sonnet-4-20250514"
    max_tokens: int = 4096
    auto_create_pr: bool = True
    require_approval: bool = True
    include_tests: bool = True
    github_owner: str = ""
    github_repo: str = ""
    branch_prefix: str = "security-fix"


@dataclass 
class Vulnerability:
    """Parsed vulnerability from GitHub issue."""
    check_id: str
    check_name: str
    severity: str
    category: str
    description: str
    affected_objects: list
    remediation_hint: str
    raw_data: dict = field(default_factory=dict)
    issue_number: int = 0


@dataclass
class SecurityFix:
    """Generated security fix."""
    vulnerability: Vulnerability
    analysis: str
    migration_sql: str
    rollback_sql: str
    test_sql: str
    explanation: str
    risk_assessment: str
    pr_description: str


class SecurityAgent:
    """
    Claude-powered agent for analyzing and fixing Supabase security vulnerabilities.
    """
    
    SYSTEM_PROMPT = """You are a senior database security engineer specializing in PostgreSQL and Supabase.
Your task is to analyze security vulnerabilities and generate safe, production-ready SQL migrations to fix them.

Guidelines:
1. ALWAYS prioritize safety - generate idempotent migrations that won't break existing functionality
2. Include rollback scripts for every change
3. Add clear comments explaining each change
4. Consider edge cases and potential side effects
5. Generate test queries to verify the fix works
6. For RLS policies, ensure they don't inadvertently block legitimate access
7. Use transactions where appropriate
8. Follow PostgreSQL best practices

Output Format:
Return your response as a JSON object with these fields:
- analysis: Detailed analysis of the vulnerability and its impact
- migration_sql: The SQL to fix the vulnerability (with comments)
- rollback_sql: SQL to undo the migration if needed
- test_sql: SQL queries to verify the fix
- explanation: Human-readable explanation for the PR
- risk_assessment: Assessment of migration risks (low/medium/high) with reasoning
"""

    def __init__(self, config: Optional[AgentConfig] = None):
        """Initialize the security agent."""
        self.config = config or AgentConfig()
        self.client = anthropic.Anthropic()
        self.github = Github(os.environ.get("GITHUB_TOKEN"))
        
        # Set config from environment if not provided
        if not self.config.github_owner:
            self.config.github_owner = os.environ.get("GITHUB_OWNER", "")
        if not self.config.github_repo:
            self.config.github_repo = os.environ.get("GITHUB_REPO", "")
    
    def get_repo(self):
        """Get the GitHub repository."""
        return self.github.get_repo(f"{self.config.github_owner}/{self.config.github_repo}")
    
    def fetch_security_issues(self, state: str = "open") -> list:
        """Fetch all open security issues from GitHub."""
        repo = self.get_repo()
        issues = repo.get_issues(state=state, labels=["security", "automated"])
        
        # Filter out already processed issues
        return [
            issue for issue in issues 
            if "security-agent-processed" not in [l.name for l in issue.labels]
        ]
    
    def parse_vulnerability(self, issue) -> Optional[Vulnerability]:
        """Parse a GitHub issue into a Vulnerability object."""
        try:
            body = issue.body
            
            # Extract structured data from issue body
            # Look for JSON in details section
            if "Raw Query Result" in body and "```json" in body:
                json_start = body.find("```json", body.find("Raw Query Result"))
                json_end = body.find("```", json_start + 7)
                raw_json = body[json_start + 7:json_end].strip()
                raw_data = json.loads(raw_json)
            else:
                raw_data = {}
            
            # Extract key information from issue
            severity = "medium"  # default
            for label in issue.labels:
                if label.name.startswith("severity:"):
                    severity = label.name.split(":")[1]
                    break
            
            # Parse affected objects from body
            affected_objects = []
            if "### Affected Objects" in body:
                section_start = body.find("### Affected Objects")
                section_end = body.find("###", section_start + 20)
                if section_end == -1:
                    section_end = len(body)
                section = body[section_start:section_end]
                
                for line in section.split("\n"):
                    if line.strip().startswith("- `"):
                        # Parse: - `schema.table` (type): details
                        obj_match = line.split("`")[1] if "`" in line else ""
                        if "." in obj_match:
                            schema, name = obj_match.split(".", 1)
                            affected_objects.append({
                                "schema": schema,
                                "name": name,
                                "type": "table"  # simplified
                            })
            
            # Extract check name from title
            title = issue.title
            check_name = title.split("]")[-1].strip() if "]" in title else title
            
            # Extract remediation hint
            remediation_hint = ""
            if "### Recommended Remediation" in body:
                rem_start = body.find("### Recommended Remediation")
                rem_end = body.find("###", rem_start + 25)
                if rem_end == -1:
                    rem_end = body.find("---", rem_start)
                if rem_end != -1:
                    remediation_hint = body[rem_start:rem_end]
            
            # Extract description
            description = ""
            if "### Description" in body:
                desc_start = body.find("### Description")
                desc_end = body.find("###", desc_start + 15)
                if desc_end != -1:
                    description = body[desc_start + 15:desc_end].strip()
            
            return Vulnerability(
                check_id=check_name.lower().replace(" ", "_"),
                check_name=check_name,
                severity=severity,
                category=self._extract_category(issue.labels),
                description=description,
                affected_objects=affected_objects,
                remediation_hint=remediation_hint,
                raw_data=raw_data,
                issue_number=issue.number
            )
            
        except Exception as e:
            logger.error(f"Failed to parse issue #{issue.number}: {e}")
            return None
    
    def _extract_category(self, labels) -> str:
        """Extract category from issue labels."""
        categories = ["rls", "authentication", "authorization", "data_exposure", 
                     "configuration", "performance", "extensions"]
        for label in labels:
            if label.name in categories:
                return label.name
        return "unknown"
    
    def analyze_and_fix(self, vulnerability: Vulnerability) -> SecurityFix:
        """Use Claude to analyze vulnerability and generate fix."""
        
        prompt = f"""Analyze this Supabase security vulnerability and generate a fix:

## Vulnerability Details

**Check Name:** {vulnerability.check_name}
**Severity:** {vulnerability.severity}
**Category:** {vulnerability.category}

**Description:**
{vulnerability.description}

**Affected Objects:**
{json.dumps(vulnerability.affected_objects, indent=2)}

**Remediation Hint:**
{vulnerability.remediation_hint}

**Raw Detection Data:**
```json
{json.dumps(vulnerability.raw_data, indent=2)}
```

## Requirements

1. Generate a safe, idempotent SQL migration to fix this vulnerability
2. Include a rollback script
3. Add test queries to verify the fix
4. Assess the risk level of this migration
5. Write a clear explanation for the PR description

Return your response as a valid JSON object with these exact keys:
- analysis (string)
- migration_sql (string) 
- rollback_sql (string)
- test_sql (string)
- explanation (string)
- risk_assessment (string)
"""

        logger.info(f"Analyzing vulnerability: {vulnerability.check_name}")
        
        response = self.client.messages.create(
            model=self.config.model,
            max_tokens=self.config.max_tokens,
            system=self.SYSTEM_PROMPT,
            messages=[
                {"role": "user", "content": prompt}
            ]
        )
        
        # Parse Claude's response
        response_text = response.content[0].text
        
        # Extract JSON from response (handle potential markdown wrapping)
        if "```json" in response_text:
            json_start = response_text.find("```json") + 7
            json_end = response_text.find("```", json_start)
            response_text = response_text[json_start:json_end]
        elif "```" in response_text:
            json_start = response_text.find("```") + 3
            json_end = response_text.find("```", json_start)
            response_text = response_text[json_start:json_end]
        
        try:
            fix_data = json.loads(response_text)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse Claude response as JSON: {e}")
            logger.debug(f"Response was: {response_text}")
            raise ValueError("Claude did not return valid JSON")
        
        # Generate PR description
        pr_description = self._generate_pr_description(vulnerability, fix_data)
        
        return SecurityFix(
            vulnerability=vulnerability,
            analysis=fix_data.get("analysis", ""),
            migration_sql=fix_data.get("migration_sql", ""),
            rollback_sql=fix_data.get("rollback_sql", ""),
            test_sql=fix_data.get("test_sql", ""),
            explanation=fix_data.get("explanation", ""),
            risk_assessment=fix_data.get("risk_assessment", ""),
            pr_description=pr_description
        )
    
    def _generate_pr_description(self, vuln: Vulnerability, fix_data: dict) -> str:
        """Generate a formatted PR description."""
        return f"""## 🔒 Security Fix: {vuln.check_name}

Closes #{vuln.issue_number}

### Summary

{fix_data.get('explanation', 'Fixes the detected security vulnerability.')}

### Vulnerability Details

- **Severity:** {vuln.severity.upper()}
- **Category:** {vuln.category}
- **Affected Objects:** {len(vuln.affected_objects)} object(s)

### Analysis

{fix_data.get('analysis', '')}

### Risk Assessment

{fix_data.get('risk_assessment', 'Risk assessment not available.')}

### Testing

Run the following queries to verify the fix:

```sql
{fix_data.get('test_sql', '-- No test queries provided')}
```

### Rollback

If issues occur, run:

```sql
{fix_data.get('rollback_sql', '-- No rollback script provided')}
```

---
*This PR was automatically generated by the Supabase Security Agent.*
"""
    
    def create_migration_files(self, fix: SecurityFix) -> dict:
        """Create migration file contents."""
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        migration_name = f"{timestamp}_security_fix_{fix.vulnerability.check_id}"
        
        return {
            f"supabase/migrations/{migration_name}.sql": f"""-- Security Fix: {fix.vulnerability.check_name}
-- Generated by Supabase Security Agent
-- Issue: #{fix.vulnerability.issue_number}
-- Severity: {fix.vulnerability.severity.upper()}
--
-- Analysis:
-- {fix.analysis.replace(chr(10), chr(10) + '-- ')}
--

{fix.migration_sql}
""",
            f"supabase/migrations/{migration_name}_rollback.sql": f"""-- Rollback for: {fix.vulnerability.check_name}
-- Run this if the migration causes issues
--

{fix.rollback_sql}
""",
            f"supabase/tests/security/{migration_name}_test.sql": f"""-- Test queries for: {fix.vulnerability.check_name}
-- Run after migration to verify the fix
--

{fix.test_sql}
"""
        }
    
    def create_pull_request(self, fix: SecurityFix) -> Optional[str]:
        """Create a GitHub PR with the fix."""
        if not self.config.auto_create_pr:
            logger.info("Auto PR creation disabled, skipping")
            return None
        
        try:
            repo = self.get_repo()
            
            # Create branch
            default_branch = repo.default_branch
            source = repo.get_branch(default_branch)
            branch_name = f"{self.config.branch_prefix}/{fix.vulnerability.check_id}-{fix.vulnerability.issue_number}"
            
            try:
                repo.create_git_ref(
                    ref=f"refs/heads/{branch_name}",
                    sha=source.commit.sha
                )
            except GithubException as e:
                if e.status == 422:  # Branch already exists
                    logger.warning(f"Branch {branch_name} already exists")
                else:
                    raise
            
            # Create migration files
            files = self.create_migration_files(fix)
            
            for filepath, content in files.items():
                try:
                    # Check if file exists
                    existing = repo.get_contents(filepath, ref=branch_name)
                    repo.update_file(
                        filepath,
                        f"fix(security): {fix.vulnerability.check_name}",
                        content,
                        existing.sha,
                        branch=branch_name
                    )
                except GithubException:
                    # File doesn't exist, create it
                    repo.create_file(
                        filepath,
                        f"fix(security): {fix.vulnerability.check_name}",
                        content,
                        branch=branch_name
                    )
            
            # Create PR
            pr = repo.create_pull(
                title=f"🔒 Security Fix: {fix.vulnerability.check_name}",
                body=fix.pr_description,
                head=branch_name,
                base=default_branch
            )
            
            # Add labels
            pr.add_to_labels("security", "automated", f"severity:{fix.vulnerability.severity}")
            
            # Add reviewers if configured
            if self.config.require_approval:
                # Get code owners or default reviewers
                try:
                    pr.create_review_request(reviewers=[])  # Add your team
                except GithubException:
                    pass
            
            logger.info(f"Created PR #{pr.number}: {pr.html_url}")
            return pr.html_url
            
        except Exception as e:
            logger.error(f"Failed to create PR: {e}")
            return None
    
    def mark_issue_processed(self, issue_number: int):
        """Add 'processed' label to the issue."""
        try:
            repo = self.get_repo()
            issue = repo.get_issue(issue_number)
            issue.add_to_labels("security-agent-processed")
            
            # Add comment with results
            issue.create_comment(
                "🤖 **Security Agent Update**\n\n"
                "This vulnerability has been analyzed and a fix has been generated.\n"
                "Please review the associated Pull Request."
            )
        except Exception as e:
            logger.error(f"Failed to mark issue #{issue_number} as processed: {e}")
    
    def process_issue(self, issue_number: int) -> Optional[str]:
        """Process a single issue by number."""
        repo = self.get_repo()
        issue = repo.get_issue(issue_number)
        
        logger.info(f"Processing issue #{issue_number}: {issue.title}")
        
        # Parse vulnerability
        vuln = self.parse_vulnerability(issue)
        if not vuln:
            logger.error(f"Could not parse vulnerability from issue #{issue_number}")
            return None
        
        # Generate fix
        fix = self.analyze_and_fix(vuln)
        
        # Create PR
        pr_url = self.create_pull_request(fix)
        
        # Mark as processed
        if pr_url:
            self.mark_issue_processed(issue_number)
        
        return pr_url
    
    def process_all_issues(self) -> list:
        """Process all unprocessed security issues."""
        issues = self.fetch_security_issues()
        results = []
        
        logger.info(f"Found {len(list(issues))} unprocessed security issues")
        
        for issue in self.fetch_security_issues():
            try:
                pr_url = self.process_issue(issue.number)
                results.append({
                    "issue": issue.number,
                    "title": issue.title,
                    "pr_url": pr_url,
                    "status": "success" if pr_url else "failed"
                })
            except Exception as e:
                logger.error(f"Failed to process issue #{issue.number}: {e}")
                results.append({
                    "issue": issue.number,
                    "title": issue.title,
                    "pr_url": None,
                    "status": "error",
                    "error": str(e)
                })
        
        return results


def main():
    """CLI entrypoint."""
    parser = argparse.ArgumentParser(
        description="Supabase Security Agent - Analyze and fix security vulnerabilities"
    )
    parser.add_argument(
        "--issue-number", "-i",
        type=int,
        help="Process a specific issue by number"
    )
    parser.add_argument(
        "--process-all", "-a",
        action="store_true",
        help="Process all unprocessed security issues"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Analyze but don't create PRs"
    )
    parser.add_argument(
        "--model",
        default="claude-sonnet-4-20250514",
        help="Claude model to use"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging"
    )
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Validate environment
    required_env = ["ANTHROPIC_API_KEY", "GITHUB_TOKEN", "GITHUB_OWNER", "GITHUB_REPO"]
    missing = [var for var in required_env if not os.environ.get(var)]
    if missing:
        logger.error(f"Missing required environment variables: {', '.join(missing)}")
        sys.exit(1)
    
    # Initialize agent
    config = AgentConfig(
        model=args.model,
        auto_create_pr=not args.dry_run
    )
    agent = SecurityAgent(config)
    
    # Process
    if args.issue_number:
        result = agent.process_issue(args.issue_number)
        if result:
            print(f"✅ Created PR: {result}")
        else:
            print("❌ Failed to create PR")
            sys.exit(1)
    
    elif args.process_all:
        results = agent.process_all_issues()
        
        success = sum(1 for r in results if r["status"] == "success")
        failed = sum(1 for r in results if r["status"] != "success")
        
        print(f"\n📊 Results: {success} successful, {failed} failed")
        for r in results:
            status = "✅" if r["status"] == "success" else "❌"
            print(f"  {status} Issue #{r['issue']}: {r.get('pr_url', r.get('error', 'unknown'))}")
    
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
