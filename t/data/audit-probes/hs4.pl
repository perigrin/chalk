my %h; if (%h) { print "y\n" } else { print "n\n" } $h{a} = 1; print "full\n" if %h; print "empty\n" unless %h; print !%h ? "e" : "ne", "\n";
