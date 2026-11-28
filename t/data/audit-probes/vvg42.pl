my %h = (a=>1); my $r = \$h{a}; delete $h{a}; $$r = 9; print exists $h{a} ? "e" : "n", "$$r\n";
