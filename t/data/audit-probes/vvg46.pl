my %h; my $r = \$h{a}{b}; $$r = 1; print join(",", keys %{$h{a}}), "\n";
