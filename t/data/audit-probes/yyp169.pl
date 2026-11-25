our $g=1; my $r=\$g; sub t { local $g=5; $$r } print t(), "\n";
