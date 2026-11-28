my %h = (k => "ab"); for (values %h) { $_ .= "c" } print "$h{k}\n";
