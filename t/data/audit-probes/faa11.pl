my %h=(a=>1); my $r=\$h{a}; delete $h{a}; $h{a}=5; print "$$r\n";
