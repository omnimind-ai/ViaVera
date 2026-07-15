import Foundation

enum AlpinePackageMirror: String, CaseIterable, Identifiable, Sendable {
    case official
    case tsinghua

    var id: Self { self }

    var title: String {
        switch self {
        case .official:
            "Alpine 官方源"
        case .tsinghua:
            "清华大学镜像源"
        }
    }

    var baseURL: String {
        switch self {
        case .official:
            "https://dl-cdn.alpinelinux.org/alpine"
        case .tsinghua:
            "https://mirrors.tuna.tsinghua.edu.cn/alpine"
        }
    }

    var repositorySetupCommand: String {
        """
        set -e
        branch="$(if [ -r /etc/alpine-release ]; then cut -d. -f1,2 /etc/alpine-release | sed 's/^/v/'; else printf '%s' 'v3.21'; fi)"
        base='\(baseURL)'
        mkdir -p /etc/apk
        printf '%s/%s/main\\n%s/%s/community\\n' "$base" "$branch" "$base" "$branch" > /etc/apk/repositories
        """
    }
}
