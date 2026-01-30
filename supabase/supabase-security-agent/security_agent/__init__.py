"""
Supabase Security Agent

A Claude SDK-powered agent that processes security vulnerability issues
and generates SQL migrations to fix them.
"""

__version__ = "1.0.0"

from .main import SecurityAgent, AgentConfig, Vulnerability, SecurityFix

__all__ = [
    "SecurityAgent",
    "AgentConfig", 
    "Vulnerability",
    "SecurityFix"
]
