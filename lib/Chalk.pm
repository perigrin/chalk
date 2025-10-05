# ABOUTME: Main Chalk module - loads all parser components
# ABOUTME: Entry point for using Chalk parser library
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw(:std :utf8);

# Load all Chalk modules
use Chalk::Base;
use Chalk::Semiring::SPPF;
use Chalk::Grammar;
use Chalk::Parser;

1;
