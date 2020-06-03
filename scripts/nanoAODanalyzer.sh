#!/bin/bash

# This script will set up CMSSW and clone & compile the repo, if needed
# Otherwise, it will 'git pull' from the master branch
# It also checks if stuff is configured (hostname, git config, git ssh keys, etc)

defineFunctions(){

    # printf format for color text [https://mywiki.wooledge.org/BashFAQ/037]
    errFormat="$( tput setaf 01)%s$(tput sgr 0 0)"
    infoFormat="$(tput setaf 02)%s$(tput sgr 0 0)"

    continuePrompt(){
        # Print 'notif' and prompt user before proceeding
        notif="$1"
        printf "\n${errFormat}\n" "${notif}"
        printf "${infoFormat}\n"  "Press <ENTER> to continue..."
        read -s -p ''
    }

    checkEmptyDir(){
        # Check if positional parameter $1 is an empty or non-existent directory [https://superuser.com/a/352387]
        find "${1}" -maxdepth 0 -type d -empty 2>&1
            # The find command will print "$1" if it is an empty directory
            # and stderr will be redirected to stdout so that it prints an error if "$1" doesn't exist
    }

    checkHostname(){
        # Exit unless running from LPC or LXPLUS
        cluster=$( hostname | cut -d'.' -f'2' )
        hostnamePrompt="Please run from FNAL:LPC or CERN:LXPLUS"
        [[ ${cluster} != "fnal" ]] && [[ ${cluster} != "cern" ]] && printf "\n${errFormat}\n" "${hostnamePrompt}" && exit
            # Check whether second field in dot-delimited 'hostname' matches 'fnal' or 'cern'
    }

    gitConfigServ(){
        # Define variables used for testing github/gitlab SSH keys, git clone, etc
        gitServ="$1"
        gitUser="$2"
        gitRepo="$3"
        [[ "${gitServ}" = "github" ]] && gitDomain="github.com"     && sett="settings" && port="22"
        [[ "${gitServ}" = "gitlab" ]] && gitDomain="gitlab.cern.ch" && sett="profile"  && port="7999"
        gitSSH="ssh://git@${gitDomain}:${port}/${gitUser}/${gitRepo}.git"
        gitKeysURL="https://${gitDomain}/${sett}/keys"
        gitTestSSH="ssh -T -p ${port} git@${gitDomain}"
    }

    gitConfigGlobal(){
        # Prompt user to set up git global config, if needed
        # [https://git-scm.com/book/en/v2/Getting-Started-First-Time-Git-Setup]
        if [[ ! -f "${HOME}/.gitconfig" ]] && [[ ! -f "${HOME}/.config/git/config" ]]; then
            printf "\n${errFormat}\n${errFormat}\n${errFormat}\n"                   \
                "Please create a GitHub account, if needed:"                        \
                "[http://cms-sw.github.io/faq.html#how-do-i-subscribe-to-github]"   \
                "And provide your name and ${gitServ} email & username:"
        fi
        gitConfigGlobalEntry "user.name"
        gitConfigGlobalEntry "user.email"
        gitConfigGlobalEntry "user.${gitServ}"
            # Required by 'git cms-init' [https://github.com/cms-sw/cms-git-tools/blob/master/git-cms-init#L151]
    }

    gitConfigGlobalEntry(){
        # Check for 'key' in git config and prompt user if missing
        key="$1"
        gitConfigGet=$( git config --get "${key}" )
        promptKey="Please provide ${gitServ} ${key}"
        [[ -z "${gitConfigGet}" ]] && ( printf "\n${errFormat}\n" "${promptKey}" && read -p "${key}: " value && git config --global "${key}" "${value}" )
            # If 'key' is missing from git config, prompt user and set it (in a sub-shell)
        # git config --global push.default simple
    }

    gitConfigKeysSSH(){
        # Test SSH key authentication for github/gitlab and guide SSH key set up if it fails; then retest
        exitCodeGitTestSSH=$( ${gitTestSSH} 2>&1 | grep -qiE 'successfully|welcome'; echo $? )
        if [[ ${exitCodeGitTestSSH} != 0 ]]; then
            keyGenSSH
            sshConfigAppend
            gitConfigKeysSSH
        fi
    }

    keyGenSSH(){
        # Create a new ssh key (with empty passphrase) and print instructions
        continuePrompt "${gitServ} SSH key authentication failed. A new ssh key will be generated at ${HOME}/.ssh/id_rsa_${gitServ}"
        # [https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent]
        # [https://docs.gitlab.com/ee/ssh/#rsa-ssh-keys]
        ssh-keygen -o -t rsa -b 4096 -N '' -C "$( git config --get user.email )" -f "${HOME}/.ssh/id_rsa_${gitServ}"
            # -o Causes ssh-keygen to save private keys using the new OpenSSH format rather than the more compatible PEM format.
                # [https://docs.gitlab.com/ee/ssh/README.html#rsa-keys-and-openssh-from-versions-65-to-78]
            # -t Specifies the type of key to create.
            # -b Specifies the number of bits in the key to create. For RSA keys, the minimum size is 1024 bits and the default is 2048 bits.
            # -N Provides the new passphrase ('' sets an empty passphrase)
            # -C Provides a new comment
            # -f Specifies the filename of the key file
        printf "\n${errFormat}\n\n" "Navigate to [${gitKeysURL}] to create a new key, and paste the following text under the 'Key' textbox:"
        cat "${HOME}/.ssh/id_rsa_${gitServ}.pub"
    }

    sshConfigAppend(){
        # Add a corresponding entry to ~/.ssh/config and re-test authentication
        continuePrompt "A 'Host ${gitDomain}' entry will be appended to ${HOME}/.ssh/config"
        printf "\n%s\n\t%s\n\t%s\n\t%s"                             \
            "Host ${gitDomain}"                                     \
            "IdentityFile                ~/.ssh/id_rsa_${gitServ}"  \
            "StrictHostKeyChecking       no"                        \
            "UserKnownHostsFile          /dev/null"                 >> "${HOME}/.ssh/config"
    }

    setupCMSSW(){
        # Set up CMSSW [https://twiki.cern.ch/twiki/bin/view/CMSPublic/WorkBookWhichRelease]
        mkdir -vp "${workingDir}"
        cd        "${workingDir}"
        export SCRAM_ARCH="${scramArch}"
        source "/cvmfs/cms.cern.ch/cmsset_default.sh"
        printf "\n${infoFormat}\n" "Setting up ${cmsswVersion}"
        cmsrel "${cmsswVersion}"
    }

    gitCheckout(){
        # Checkout and compile repo
        printf "\n${infoFormat}\n" "Running 'git cms-init'"
        git cms-init # [https://cms-sw.github.io/tutorial-merge-usercode-repository-in-cmssw.html]
        printf "\n${infoFormat}\n" "Running 'git clone ${gitSSH}"
        git clone "${gitSSH}"
        cd "${workingDir}/${cmsswVersion}/src/${gitRepo}"
        git checkout master
        git pull
        printf "\n${infoFormat}\n" "Compiling..."
        make -j8
        [[ "$?" != 0 ]] && printf "\n${errFormat}\n" "Please see [https://github.com/VandyHEP/NanoAOD_Analyzer/wiki/Troubleshooting-(*)]"
    }

}

main(){
    checkHostname
    gitConfigServ 'github' 'VandyHEP' 'NanoAOD_Analyzer' # [https://github.com/VandyHEP/NanoAOD_Analyzer/wiki/Installation]
    gitConfigGlobal
    gitConfigKeysSSH
    workingDir="${HOME}/nobackup/${gitRepo}"
    cmsswVersion="CMSSW_10_2_18"
    scramArch="slc7_amd64_gcc700"
    [[ $( checkEmptyDir "${workingDir}/${cmsswVersion}" ) ]] && setupCMSSW
    cd "${workingDir}/${cmsswVersion}/src"
    cmsenv
    [[ $( checkEmptyDir "${workingDir}/${cmsswVersion}/src/${gitRepo}" ) ]] && gitCheckout
    cd "${workingDir}/${cmsswVersion}/src/${gitRepo}"
    git checkout master
    git pull
    # git branch   "${USER}"
    # git checkout "${USER}"
}

if [[ "$0" = "$BASH_SOURCE" ]]; then
    # [https://stackoverflow.com/a/59274815/13019084]
    printf "\n%s\n%s\n" "Please 'source' the script instead of executing it:" "source ${0/.\//}"
else
    # Run main function in a sub-shell when the script is 'sourced' (source nanoAODanalyzer.sh)
    # so that all functions and variables are local and it can 'exit' without logging out the ssh session
    ( defineFunctions; main )
    # unset all functions
    # unset -f continuePrompt checkHostname gitConfigServ gitConfigGlobal gitConfigKeysSSH keyGenSSH sshConfigAppend
    # unset -f setupCMSSW checkEmptyDir gitCheckout main
fi
