my %h = (a=>undef); print exists $h{a} ? "e" : "n", defined $h{a} ? "d" : "u", "\n";
