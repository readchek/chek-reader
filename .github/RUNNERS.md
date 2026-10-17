# Self-hosted runners

CI can run on the maintainers' own machines instead of GitHub's runners: a Mac mini for the Apple jobs and a Linux server for the Linux jobs. Each machine is switched on by a repository variable, so either can be turned off at any time and its jobs go back to GitHub's runners.

| Variable | Runner labels | Jobs |
| --- | --- | --- |
| `SELF_HOSTED_MAC` = `true` | `self-hosted`, `chek-mac` | Apple platforms in CI; benchmark build and fixtures |
| `SELF_HOSTED_LINUX` = `true` | `self-hosted`, `chek-linux` | Core on Linux in CI; benchmark summary |

Pull requests from forks always use GitHub's runners, because this repository is public and a fork's code could otherwise run on these machines. The reader script job and the benchmark fixture list stay on GitHub's runners too: they run on the host rather than in a container, and the script job installs system packages as root.

## Repository settings

1. **Settings → Actions → General → Fork pull request workflows from outside collaborators**: choose **Require approval for all external contributors**.
2. Register each machine below, and check it shows as **Idle** under **Settings → Actions → Runners**.
3. **Settings → Secrets and variables → Actions → Variables**: add `SELF_HOSTED_MAC` and `SELF_HOSTED_LINUX`, each set to `true`, once its machine is idle. Set one to `false` to send its jobs back to GitHub, for example while the machine is down: queued jobs otherwise wait for it.

Each machine needs a registration token, which **Settings → Actions → Runners → New self-hosted runner** shows with the download link for that platform. A token expires after an hour.

## Mac mini

The runner runs as a LaunchAgent in a logged-in session, because the iOS Simulator needs one.

1. Create a standard user named `runner`, and turn on **System Settings → Users & Groups → Automatically log in as** `runner`.
2. Keep the machine awake and have it restart after a power cut:
   ```sh
   sudo pmset -a sleep 0 disksleep 0 autorestart 1
   ```
3. Signed in as `runner`, install Xcode 27 at `/Applications/Xcode.app`, then:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   sudo xcodebuild -license accept
   xcodebuild -runFirstLaunch
   xcodebuild -downloadPlatform iOS
   ```
4. Install [Homebrew](https://brew.sh) and follow its note to add it to `~/.zprofile`. The benchmarks install XcodeGen with it.
5. Install the runner from a new Terminal window, so `brew` and `xcodebuild` are on the `PATH` the runner saves:
   ```sh
   mkdir ~/actions-runner && cd ~/actions-runner
   curl -o runner.tar.gz -L <macOS ARM64 download link from the settings page>
   tar xzf runner.tar.gz
   ./config.sh --url https://github.com/readchek/chek-reader --token <token> \
     --name mac-mini --labels chek-mac --unattended
   ./svc.sh install
   ./svc.sh start
   ```

Builds reuse `~/Library/Developer/Xcode/DerivedData`, which is most of the speed gain. If it grows too large or a build behaves oddly, delete it.

## Linux server

Jobs here run in the `swift:6.4-noble` container, so the server needs Docker but not Swift. These steps assume Ubuntu or Debian.

1. Install Docker and create the runner's user. Membership of the `docker` group is equivalent to root on this machine, which is why forks never reach it.
   ```sh
   sudo apt-get update && sudo apt-get install -y docker.io curl
   sudo useradd -m -s /bin/bash runner
   sudo usermod -aG docker runner
   ```
2. Install the runner as that user:
   ```sh
   sudo -iu runner
   mkdir actions-runner && cd actions-runner
   curl -o runner.tar.gz -L <Linux download link for this machine's architecture>
   tar xzf runner.tar.gz
   ./config.sh --url https://github.com/readchek/chek-reader --token <token> \
     --name ovh --labels chek-linux --unattended
   docker pull swift:6.4-noble
   exit
   ```
3. Install its dependencies and run it as a service:
   ```sh
   cd /home/runner/actions-runner
   sudo ./bin/installdependencies.sh
   sudo ./svc.sh install runner
   sudo ./svc.sh start
   ```

Only container jobs are routed here, because a container writes files as root and a later job on the host couldn't clean them up. If a job ever fails with a permission error cleaning `_work`, run `sudo chown -R runner /home/runner/actions-runner/_work`.
