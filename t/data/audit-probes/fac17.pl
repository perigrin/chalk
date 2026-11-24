my %h=(a=>1); sub g { return %h } my %c=g(); $c{a}=5; print "$h{a}\n";
