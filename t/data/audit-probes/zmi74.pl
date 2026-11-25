my %h=(a=>1); print %h ? "t" : "f", scalar(%h), !%h ? "e" : "n"; %h=(); print %h ? "t" : "f", "\n";
