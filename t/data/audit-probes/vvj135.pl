my %h = (a=>1,b=>2); if (%h) { print "t" } print scalar(keys %h), !%h ? "e" : "n", "\n";
