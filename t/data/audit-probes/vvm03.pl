our %h = (a=>1); { local %h; } print join(",", sort keys %h), "\n";
