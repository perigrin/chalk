our %h = (a=>1); { local %h = (b=>2); } print join(",", sort keys %h), "\n";
