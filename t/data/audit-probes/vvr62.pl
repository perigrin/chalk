my %h = (a=>1,b=>2); my $r = \$h{a}; delete $h{a}; $h{a} = 5; print "$$r\n";
