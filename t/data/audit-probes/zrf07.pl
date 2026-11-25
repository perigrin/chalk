my %h=(k=>1); my $r=\$h{k}; delete $h{k}; $h{k}=2; print "$$r$h{k}\n";
