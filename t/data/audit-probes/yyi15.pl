sub inc { $_[0]++ } my %h=(a=>1); inc(values %h); inc(%h); print "$h{a} ", join(",", keys %h), "\n";
