my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); my $n = () = delete @h{@k}; print "$n", scalar(keys %h), "\n";
