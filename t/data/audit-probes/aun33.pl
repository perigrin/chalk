my %h=(a=>1,b=>2); for (1..3) { @h{qw(a b)} = @h{qw(b a)} } print "$h{a} $h{b}\n";
