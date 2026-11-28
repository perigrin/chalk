my %h = (a=>1); my $r = \$h{a}; $h{a} = 2; print "$$r\n";
