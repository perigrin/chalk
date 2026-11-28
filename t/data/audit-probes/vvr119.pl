my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); my $l = delete @h{@k}; print "$l", scalar(keys %h), "\n";
