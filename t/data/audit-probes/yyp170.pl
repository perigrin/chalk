our $g=1; my $r=\$g; sub t { local $g=5; $$r=7; $g } print t(), "$g\n";
