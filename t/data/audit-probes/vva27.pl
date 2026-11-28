our %h = (a=>1,b=>2); { delete local $h{a}; print join(",", sort keys %h), ";" } print join(",", sort keys %h), "\n";
