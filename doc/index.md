# Notes
> Thu Aug 25 10:36:17 BST 2016

# Emacs as tmux replacement

Before moving back to Emacs I did what many people do - built an IDE of sorts by
combining Vim, Tmux and Bash. By clever use of scripting, REPLs and such one can
glue all these tools together to have things like 'open a new shell and this text to it'
done quite trivialy.

## Brave new world

After refreshing my muscle memory and building [a sane config](https://github.com/lukaszkorecki/cult-leader) I proceeded to simply replace Vim with Emacs.

One of the reasons for switching was that I get write a lot of Lisp - mostly Clojure and some Scheme ([Chicken Scheme](http://call-cc.org/) in particular, but I'm also looking at [Racket](https://racket-lang.org)). Naturaly, [Emacs being a sort of Lisp Machien](https://www.emacswiki.org/emacs/LispMachine) the tooling for working with Lisps is fenomenal. Tools like [CIDER](https://github.com/clojure-emacs/cider) and [Geiser](http://www.nongnu.org/geiser/) show how Emacs can shine as an IDE, without being a huge mess of a GUI and a resource hog.
Inspired by these tools I started exploring things like [inf-ruby](https://github.com/nonsequitur/inf-ruby) and running terminals withing Emacs (via [ansi-term](https://www.emacswiki.org/emacs/AnsiTerm)  more often than opening tmux windows and panes. There is simply no need.

## Removing tmux

 Using [daemon mode](https://www.emacswiki.org/emacs/EmacsAsDaemon) in Emacs one can replicate all features (and more) of tmux/screen:

 - sessions can be suspended and resumed
 - universal copy and paste between terminal any type of a buffer
 - window/pane layout management
 - tmux 'windows' can be emulated with packages like [eyebrowse](https://github.com/wasamasa/eyebrowse)

 ## `ssh-agent` issue

 Because I work in a Vagrant VM one of the issues I kept running into was that after ssh'ing back to the tmux session, all currently active shell sessions
 would lose connection to the `ssh-agent`.

 With a simple shell script:

 ```bash
 if pgrep -f emacs ; then
  emacs --daemon

fi

emacsclient -nw

 ```

 and [an extra package](https://github.com/lukaszkorecki/cult-leader/commit/17ed38e4fe5e6b6f2140ebf97e5b798118b652a7) I can now use [magit](https://magit.vc/) without any issues.


## Issues?

Only issue I keep running into is that a long running (week?) Emacs session sometimes becomes corrupted and syntax higlighting stops to work.
I haven't found a fix for this, but given my experience with Emacs so far the fix surely exists :-)

---

> Sat Jul 30 14:56:25 BST 2016

I'm still pretty new to JVM land, despite of using Clojure in production for a year and some random past episodes of working on Android and JRuby projects.
With that I'm still finding some oddities and unexpected things in how JVM based languages work and manage certain things.

## Expectations

For example - when packaging a Ruby project into a gem, it's pretty safe to assume that if your library ships with a resource file (for example a html template), it can be read like this:

```ruby

class Foobar
  TEMPLATE = File.read(File.expand_path('./tmpl.txt', __FILE__))
end

```

This pretty much guarantees that if `foobar.rb` and `tmpl.txt` are in the same dir, no matter where and how the gem is installed or if we're just running the code via `ruby ./lib/foo/foobar.rb`.

In Java/JVM land things are not so simple.

Above snippet would work, however if we're creating and distributing a library as a `jar` file things are getting complicated.


## Real world

My scenario was this:

- I have a service written 100% in Clojure (let's call it `foo`, obviously)
- I have a library `bar`, also 100% in Clojure
- Library `baz` is 99% Java and 1% is a Clojure wrapper, additionaly `baz` needs static resource files to work (think configuration/db for a NLP model)

`foo` depends on `bar` and `baz`.

As I'm using [bintray](https://bintray.com) to host a private Maven repo, things are pretty simple. With Leiningen all I have to do is add:

```clojure

;; used for publishing as a lib
 :deploy-repositories [["releases"
                         {:url "https://api.bintray.com/maven/repo/maven/bar/;publish=1"
                          :sign-releases false
                          :username :env/bintray_username
                          :password :env/bintray_api_key}]
                        ["snapshots"
                         {:url "https://api.bintray.com/maven/repo/maven/bar/;publish=1"
                          :sign-releases false
                          :username :env/bintray_username
                          :password :env/bintray_api_key}]]

```

to `project.clj` and run `lein deploy`. This will compile everything, create a maven package and upload it to Bintray.

Then in `foo`'s `project.clj`:

```clojure
 :repositories [["bintray"
                 {:url "https://repo.bintray.com/maven"
                  :snapshots true
                  :username :env/bintray_username
                  :password :env/bintray_api_key}]]
```

will make private libs available as dependencies.

### So far so good

As one would expect `baz` the Java/Clojure lib proved to be a bit problematic:

- extra resource file was read at runtime, and the code assumed it's available under `resources/db.txt`
- when deployed as a jar (even locally, using `lein install`) the file would get included
- **however** using `baz` as a dependency in `foo` wouldn't work as the file's path would no longer be a file system path, but instead it would get turned into a [resource](https://docs.oracle.com/javase/8/docs/technotes/guides/lang/resources.html).

My first approach was to convert all the code from simply reading files from paths to using resources:

```java
// before

class SomeStuff {
  private final db;

  public void SomeStuff(String pathToDB) {
    db = new BufferedReader(new FileReader(pathToDB));
  }
}

// after

// in tests
InputStream in = this.getClass().getResourceAsStream(pathToDB);

class SomeStuff {
  private final db;

  public SomeStuff(InputStream db)
    db = new BufferedReader(new InputStreamReader(db));
  }

}


```

then in Clojure:

```clojure

;; before
(SomeStuff. "resources/db.txt")

;; after

(require '[clojure.java.io :as io]

(SomeStuff. (-> "db.txt"
                io/resource
                io/file
                io/input-stream))

```

I've run the test and pushed to our CI server. Everything works.
Tested the code in REPL, all fine.

# Neat

After `lein install` I've happily used `baz` code in `foo` and run the tests and...


```

billion lines of stacktraces

Caused by: java.lang.IllegalArgumentException: Not a file: jar:file:/home/vagrant/.m2/repository/baz/baz/1.0.7-SNAPSHOT/baz-1.0.7-SNAPSHOT.jar!/db.txt

```


Since `jar` files are just zips, I've peeked inside and `db.txt` was there. Both Clojure and JUnit tests were passing fine in `baz` so... What. The. Hell?


I've started checking out how other people do this since Googling didn't help much. Very quickly I realized my mistake. You see `java.io.InputStream` knows how to deal with many things - not only Files but also... Resources.


So:

```clojure

;; before

(require '[clojure.java.io :as io]

(SomeStuff. (-> "db.txt"
                io/resource
                io/file
                io/input-stream))

;; after


(SomeStuff. (-> "db.txt"
                io/resource
                io/input-stream))

```
Seemed like a bit of a random change but:

- tests in `baz` worked just fine
- after installing to a local Maven repository `foo` pulled `baz` just fine
- tests in `foo` worked as expected


## Summary

TIL how to:

- ship a mixed Clojure/Java project as a lib
- that lib has some resources (that are not code)
- and how to use all that in *another* Clojure project

---

> Mon Jul 11 11:51:48 BST 2016

# Debugging of statsd-like monitoring

While working on [statsd reporter lib for Chicken Scheme](https://github.com/lukaszkorecki/statsd-chicken)
I had to check if stats are actually being sent.
Setting up statsd and graphite is quite... involved, luckily there's couple
projects based on Docker which give a full Grafana + Graphite + Statsd setup.

That works fine, but this is still too much if I just want to see if the metrics
are being sent at all and if so - in what format.

While researching completely unrelated thing (state of web frameworks in Clojure),
I stumbled upon [monitoring example in Pedestal project](https://github.com/pedestal/pedestal/tree/master/samples/helloworld-metrics#statsd-metrics-reporting) which has a really nifty snippet:

```shell
nc -kul 8125
```

`netcat` is a swiss army knife of networking and the snippet above will create
a "server" which will listen for UDP packets on port 8125. Easy

This reminded me that in the past I used the following:

```shell

echo "some.random.stat:$RANDOM|g" | nc -u -w1 127.0.0.1 8125
```

to test collectd's [statsd plugin](https://collectd.org/wiki/index.php/Plugin:Statsd)

---

> Sat Jul 16 11:52:09 BST 2016

# Using OS X for development considered harmful

I have been using virtual machines for all my programming work for nearly 5 years now. It’s very unlikely that I will ever set up any development environment on a real machine ever again.

## When Ruby 1.9 was the next big thing

In order to set myself up when I started working at one job I had to:

- Compile the server core by hand (it was written in C++ and required specific version of boost)
- Install a handful for python packages (that was around when `easy_install` was the first choice for dependency management), most of which wouldn’t work on OSX
- Get the rest of the stack running (regular Ruby 1.8.7 + Passenger + Rails 2)

Doesn’t sound that bad — it took a day or two to get fully set up. If you were lucky.

I was lucky and I could take the easy way out and skip to point 3 and use staging server as the rest of my stack. Of course life is not all roses and it all was depending on the quality of the internet connection. Which of course was terrible.

SSH tunnels while a great idea, don’t work very well on bad connections.

## Going cyber virtual internet

Around that time Vagrant wasn’t even at v1 but it looked like the next best thing.

I got myself a Vagrant powered machine, wrote some shell scripts and… I never looked back.

Gradually I moved all my development stack to the VM, learned to be better at using tmux (by that time I was a full time Vim user anyway so I didn’t miss any GUI).

That was in 2011. Since then whenever I started at new job I had two choices:

- Spend 2 days getting my Mac set up
- Spend half a day, automate as much possible and benefit everyone whoever joins after me — even if they will not use the VM like I do, at least all other dependencies (DBs, queue systems etc) are all in place
- VM setup was as close as possible to production so there were additional debugging benefits

Of course switching 100% to a VM based environment is not without problems.

### No GUI

if you’re used to text editors like Sublime Text and you absolutely have to see all your files in Finder (or whatever), you’re going to have a hard time.

### It’s not a real machine!

VirtualBox (and others) have their quirks and you’ll never get that raw, bare metal speed — that said, your dev machine shouldn’t be used for benchmarking either.

### One machine to rule them all

One mistake I made was to create one Vagrant machine for everything — host the DB, run code, tests. This quickly bit my ass when my whole team started using VMs.

I decided to split my setup into multiple VMs — one for work, other for application dependencies (Redis, Postgres, Elasticsearch etc).

This is when I hit my biggest obstacle — work became unbearable. Sure, everything is automated and all that but I can barely use Firefox. My Macbook Air can barely keep up and it doesn’t look like I will be able to upgrade my machine anytime soon.

## The cloud ☁

>️ How can I upgrade this machine by not spending too much money?

I had this idea for a while and I kinda did it before (see beginning of this post).

I’ve looked at AWS free tier machines and realized that t2.medium instance offers quite nice balance between what I need and the price. If it’s too slow — I can get couple of free tier instances and farm out other dependencies while keeping faster machine to myself.

Of course all that is not set up by hand — I already had a way of provisioning virtual machines, I just had to move the machines off my computer into the cloud ⛅️

## 1979

This is the promise of ChromeBooks, but taken to extreme. All my machines can burn down and if I’m in a real pinch all I need is something connected to the internet, SSH client and a terminal emulator.

Don’t get me wrong — I still keep a trusty VM around for offline work, but in the times of tethering, super cheap EU roaming (thanks O2) and mosh it doesn’t really feel that much different than the workflow I’ve been using for last 5 years.

I took it as far as I can, I have 3 VMs which I use everyday:

Comms — permanent tmux session with Weechat (connected to 3 Slack and 1 Freenode account) and Mutt
Work — this is were I work
Storage — hosts databases and other services (Elasticsearch, Redis etc)

It pays off to write shell scripts and be comfortable with the terminal.


---

#### Update

I'm back on Vagrant - after 9 months of working exclusively in the cloud I got myself a Macbook Pro
with enough CPU and RAM to replicate my remote setup locally.

Main reason was that I started traveling more often and more often than not I'd be using crappy
internet connections.

That said - because of all that experience, migrating back was as easy as it could get. For the most
part it was updating hostnames in my `~/.ssh/config`.

---

