my $str=""; my %h=(b=>2,a=>1,c=>3); for my $k (sort { $h{$b} <=> $h{$a} } keys %h) { $str.="$k$h{$k}" } print "$str\n";
