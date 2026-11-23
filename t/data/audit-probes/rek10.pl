my %h=(a=>1); sub cp { my %c=@_; $c{a}=2; } cp(%h); print "$h{a}\n";
