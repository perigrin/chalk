my %h = (a=>1,b=>2); my $r = \$h{a}; %h = (%h); $$r = 9; print "$h{a}\n";
