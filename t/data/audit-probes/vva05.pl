our %h = (a=>1); { local $h{z} = 8; print join(",", sort keys %h), ";" } print join(",", sort keys %h), "\n";
