my %h=(a=>1); sub cl { %h=() } my $n=0; while (%h) { cl(); $n++ } print "$n\n";
