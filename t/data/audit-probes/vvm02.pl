our %h = (a=>1); { local %h = (b=>2); print $h{b} } print join(",", sort keys %h), "\n";
