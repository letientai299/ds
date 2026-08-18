(def support
  @{:targets [{:os :macos :arch :arm64 :libc :system}
              {:os :macos :arch :x64 :libc :system}
              {:os :linux :arch :arm64 :libc :musl}
              {:os :linux :arch :arm64 :libc :glibc}
              {:os :linux :arch :x64 :libc :musl}
              {:os :linux :arch :x64 :libc :glibc}]
    :shells [:sh :zsh]
    :bootstrap {:privilege :unprivileged
                :required-commands ["sh" "mkdir" "cat" "chmod"]}
    :rootful {:policy :explicit-approval}})
