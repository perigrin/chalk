my %h = (a=>1,b=>2,c=>3); my @k = qw(b c); my @v = @h{@k}; print "@v\n";
