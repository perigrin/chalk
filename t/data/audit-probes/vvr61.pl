my %h = (a=>1,b=>2); my $r = \$h{a}; my $v = delete $h{a}; $h{a} = 5; $$r = 9; print "$h{a}$v\n";
