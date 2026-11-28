my %h = (a=>1,b=>2); my $r = \$h{a}; ($h{a}, $h{b}) = ($h{b}, $h{a}); $$r = 9; print "$h{a}$h{b}\n";
