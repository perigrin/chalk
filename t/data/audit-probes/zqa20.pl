my @a=(1,2); sub f { my %h=(l=>[@_]); $a[0]=9; "@{$h{l}}" } print f(@a), "\n";
