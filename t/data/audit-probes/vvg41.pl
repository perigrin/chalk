my %h = (a=>1); my $r = \$h{a}; $$r = 9; print "$h{a}\n";
