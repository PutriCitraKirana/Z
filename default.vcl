vcl 4.1;

import std;

backend default {
    .host = "209.38.141.100";
    .port = "443";
    .first_byte_timeout = 60s;  // Reduced from 300s
    .connect_timeout = 2s;     // Faster connection timeout
    .between_bytes_timeout = 5s;
}

sub vcl_recv {
    # Ultra-aggressive caching for small files
    if (req.url ~ "\.(txt|json|ico|js|css)$") {
        unset req.http.Cookie;
        unset req.http.Authorization;
        return (hash);
    }

    # Special handling for HTTP/1.1
    set req.http.connection = "close";

    # Force HTTPS
    if (req.http.X-Forwarded-Proto !~ "https") {
        return (synth(301, "https://" + req.http.host + req.url));
    }
}

sub vcl_backend_response {
    # Micro-optimization for small files (<1MB)
    if (beresp.http.Content-Length) {
        if (std.integer(beresp.http.Content-Length, 0) <= 1048576) {
            # Override origin TTL for small files
            set beresp.ttl = 24h;  // Increased from 300s
            set beresp.grace = 2h;
            
            # Optimization flags
            set beresp.do_stream = false;  // Force buffering
            set beresp.do_gzip = true;
            
            # Remove unnecessary headers
            unset beresp.http.Last-Modified;
            unset beresp.http.ETag;
        }
    }
    
    # Force caching even for dynamic small files
    if (beresp.http.Content-Length <= 1024) {
        set beresp.http.Cache-Control = "public, max-age=86400";  // Override origin
        set beresp.ttl = 5m;  // Set TTL for small files to 5 minutes
    } else {
        set beresp.http.Cache-Control = "public, max-age=86400";  // Override origin for larger files
    }
    
    unset beresp.http.Set-Cookie;
    
    # Special handling for 0-byte files
    if (beresp.http.Content-Length == "0") {
        set beresp.ttl = 5m;
    }
}

sub vcl_deliver {
    # Enhanced timing headers
    set resp.http.X-Origin-TTFB = req.http.X-TTFB;
    set resp.http.X-Cache-State = obj.hits > 0 ? "HIT" : "MISS";
    
    # Performance headers
    set resp.http.X-Content-Type-Options = "nosniff";
    set resp.http.X-Frame-Options = "SAMEORIGIN";
    
    # Debug info for small files
    if (resp.http.Content-Length && std.integer(resp.http.Content-Length, 0) < 1024) {
        set resp.http.X-Cache-Debug = "Small-File-Optimized";
    }
}

sub vcl_hit {
    # Immediate delivery for small files
    if (obj.size <= 1024) {
        return (deliver);
    }
}

sub vcl_miss {
    # Fast fetch for small files
    if (req.http.Content-Length && std.integer(req.http.Content-Length, 0) <= 1024) {
        set bereq.http.X-FastFetch = "1";
    }
    return (fetch);
}