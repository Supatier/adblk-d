import core.stdc.stdlib : exit, EXIT_FAILURE, EXIT_SUCCESS;
import core.sys.posix.unistd : getuid;
import std.array : array;
import std.conv : text, to;
import std.file : append, copy, exists, readText, writeFile = write;
import std.getopt : getopt;
import std.json : JSONValue, parseJSON;
import std.net.curl : byLineAsync;
import std.process : executeShell;
import std.regex : matchAll, regex, replaceAll;
import std.stdio : write, writeln;

/// Prints help
void usage() {
        write("
adblk-d
Usage:	adblk-d [options]

Options:
  --b,  --before        Path to the before file
  --s,  --staging       Path to the staging file
  --t,  --target        Target IP address
        --hosts         Path to hosts file
  --w,  --whitelist     Path to whitelist (link shortener recommended)
  --c,  --cfg           Path to config.json
  --h,  --help          Print this help
");
}

string cleanJSONstring(JSONValue input) {
        string output = replaceAll(text(input), regex(r"\\"), "");
        output = replaceAll(output, regex("\""), "");
        return output;
}

void main(string[] args) {

        bool help;
        /// Default variables. Can be change in config.json
        string beforeFile = "/tmp/block.build.list";
        string stagingFile = "/tmp/block.build.stg";
        string target = "0.0.0.0";
        string hosts = "/etc/hosts";
        string whitelist = "/tmp/white.list";

        /// Change with or --c --cfg only.
        string configLocation = "/etc/config.json";

        string beforeFileNew;
        string stagingFileNew;
        string targetNew;
        string hostsNew;
        string whitelistNew;
        getopt(args, "c|cfg", &configLocation, "h|help", &help, "b|before", &beforeFileNew,
                        "s|staging", &stagingFileNew, "t|target", &targetNew,
                        "hosts", &hostsNew, "w|whitelist", &whitelistNew);

        if (help) {
                usage();
                exit(EXIT_SUCCESS);
        }

        if (exists(configLocation)) {
                JSONValue[string] config = parseJSON(readText(configLocation)).object;
                beforeFile = cleanJSONstring(config["beforeFile"]);
                stagingFile = cleanJSONstring(config["stagingFile"]);
                target = cleanJSONstring(config["target"]);
                hosts = cleanJSONstring(config["hosts"]);
                whitelist = cleanJSONstring(config["whitelist"]);

                if (beforeFileNew.length != 0)
                        beforeFile = beforeFileNew;
                if (stagingFileNew.length != 0)
                        stagingFile = stagingFileNew;
                if (targetNew.length != 0)
                        target = targetNew;
                if (hostsNew.length != 0)
                        hosts = hostsNew;
                if (whitelistNew.length != 0)
                        whitelist = whitelistNew;

                const int uid = getuid();
                if (uid != 0) {
                        writeln("Warning: Must run as root
It may not work");
                }
                writeFile(beforeFile, "");

                JSONValue[] noroute = config["noroute"].array;
                foreach (i, e; noroute) {
                        auto pattern = regex(r"(^0.0.0.0)");
                        string server = cleanJSONstring(e);
                        writeln("Downloading from ", server);
                        foreach (line; byLineAsync(server)) {
                                if (matchAll(line, pattern) && !matchAll(line, regex(r"(^#)"))) {
                                        auto stream = text(replaceAll(line, pattern, target), "\n");
                                        append(beforeFile, stream);
                                }
                        }
                        writeln("Done");
                }

                JSONValue[] localhost = config["localhost"].array;
                foreach (i, e; localhost) {
                        auto pattern = regex(r"(^127.0.0.1\t)");
                        string server = cleanJSONstring(e);
                        server = replaceAll(server, regex("\""), "");
                        writeln("Downloading from ", server);
                        foreach (line; byLineAsync(server)) {
                                if (matchAll(line, pattern) && !matchAll(line, regex(r"(^#)"))) {
                                        auto stream = text(replaceAll(line,
                                                        pattern, text(target, " ")), "\n");
                                        append(beforeFile, stream);
                                }
                        }
                        writeln("Done");
                }

                JSONValue[] empty = config["empty"].array;
                foreach (i, e; empty) {
                        string server = cleanJSONstring(e);
                        writeln("Downloading from ", server);
                        foreach (line; byLineAsync(server))
                                if (!matchAll(line, regex(r"(^#)"))
                                                && !matchAll(line, regex(r"(^\s*$)"))) {
                                        auto stream = text(target, " ", line, "\n");
                                        append(beforeFile, stream);
                                }
                        writeln("Done");
                }

                auto command = text(`awk '{sub(/\\r$/,"");print $1,$2}' `,
                                beforeFile, " | sort -u > ", stagingFile);
                executeShell(command);
                writeFile(hosts, "127.0.0.1  localhost localhost.localdomain localhost4 localhost4.localdomain4\n::1  localhost localhost.localdomain localhost6 localhost6.localdomain6 ip6-localhost ip6-loopback\nfe00::0 ip6-localnet\nff00::0 ip6-mcastprefix\nff00::0 ip6-mcastprefix\nff02::2 ip6-allrouters\nff02::3 ip6-allhosts\n");

                if (exists(whitelist)) {
                        command = text(`egrep -v "^[[:space:]]*$" `, whitelist,
                                        ` | awk '/^[^#]/ {sub(/\r$/,"");print $1}' | grep -vf - "`,
                                        stagingFile, `" >> `, hosts);
                        executeShell(command);
                } else {
                        copy(stagingFile, hosts);
                }
        } else {
                writeln("===== Config file not found =====");
                exit(EXIT_FAILURE);
        }
}
