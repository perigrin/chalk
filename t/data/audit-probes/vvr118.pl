my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); if (delete @h{@k}) { print "t" } print scalar(keys %h), "\n";
