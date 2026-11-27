my %h=(k=>1); my $r=\$h{k}; %h = (k=>3); print "$$r $h{k}\n";
